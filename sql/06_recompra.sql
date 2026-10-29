-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 06: Recompra - ¿qué distingue a los clientes que vuelven?
-- Motor: MySQL 8
-- =====================================================================
-- Pregunta: ¿una mala primera experiencia (mala nota, atraso) hace que el
-- cliente no vuelva a comprar?
--
-- Antes de comparar hay que definir bien qué es "volver", por dos trampas:
--   1. Dos pedidos el mismo día no son recompra: el cliente aún no había
--      recibido nada (por ejemplo, olvidó agregar un producto).
--   2. No todos tuvieron el mismo tiempo para volver: quien compró por
--      primera vez en agosto de 2018 casi no tiene datos posteriores.
--      No hay que confundir "no volvió" con "no alcanzamos a verlo".
--
-- Técnicas: ROW_NUMBER y LAG con PARTITION BY por cliente, MIN() OVER,
-- MAX de una condición ("¿existe al menos uno?") y MAX(CASE ...) para
-- llevar los datos de la primera compra a una fila por cliente.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. ¿Cuánto tiempo pasa entre la primera y la segunda compra?
-- ---------------------------------------------------------------------
-- PARTITION BY customer_unique_id: la numeración y el LAG se calculan
-- dentro de cada cliente. En la segunda compra (n_compra = 2), el LAG trae
-- la fecha de la primera.

WITH compras AS (
    SELECT customer_unique_id,
           fecha_compra,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY fecha_compra) AS n_compra,
           LAG(fecha_compra) OVER (PARTITION BY customer_unique_id ORDER BY fecha_compra) AS compra_anterior
    FROM v_pedidos
)
SELECT CASE
           WHEN DATEDIFF(fecha_compra, compra_anterior) = 0   THEN '1. Mismo día'
           WHEN DATEDIFF(fecha_compra, compra_anterior) <= 30  THEN '2. 1 a 30 días'
           WHEN DATEDIFF(fecha_compra, compra_anterior) <= 90  THEN '3. 31 a 90 días'
           WHEN DATEDIFF(fecha_compra, compra_anterior) <= 180 THEN '4. 91 a 180 días'
           ELSE                                                     '5. Más de 180 días'
       END AS tiempo_hasta_segunda,
       COUNT(*)                                         AS clientes,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM compras
WHERE n_compra = 2
GROUP BY tiempo_hasta_segunda
ORDER BY tiempo_hasta_segunda;

/* Resultado:

   tiempo hasta la segunda compra   clientes     %
   1. Mismo día                          867    30,2
   2. 1 a 30 días                        597    20,8
   3. 31 a 90 días                       503    17,5
   4. 91 a 180 días                      423    14,7
   5. Más de 180 días                    484    16,8

   - El 30% de los clientes con una segunda compra la hizo el mismo día:
     no es recompra real. Contarlos inflaría la recompra.
   - De los que vuelven en otro día (2.007), el 76% lo hace dentro de 180 días.

   Definición adoptada:
   - Un cliente VOLVIÓ si hizo otra compra, en un día distinto, dentro de
     los 180 días siguientes a su primera compra.
   - Solo son ELEGIBLES los clientes con primera compra antes del
     2018-03-01. Los datos terminan a fines de agosto de 2018, así que todos
     los elegibles tuvieron al menos 6 meses para volver. */

-- ---------------------------------------------------------------------
-- 2. Vista v_clientes: una fila por cliente
-- ---------------------------------------------------------------------
-- Contiene la marca de recompra, la elegibilidad y los datos de la
-- PRIMERA compra de cada cliente.
--   - MIN(fecha_compra) OVER (PARTITION BY ...): anota en cada pedido la
--     fecha de la primera compra de su cliente, sin juntar las filas.
--   - MAX(condición): la condición vale 1 o 0 en cada pedido; si algún
--     pedido la cumple, el máximo es 1 ("¿existe al menos uno?").
--   - MAX(CASE WHEN n_compra = 1 ...): toma los datos de la primera compra
--     y los deja en la fila del cliente.

CREATE OR REPLACE VIEW v_clientes AS
WITH compras AS (
    SELECT p.*,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY fecha_compra) AS n_compra,
           MIN(fecha_compra) OVER (PARTITION BY customer_unique_id)                  AS primera_compra
    FROM v_pedidos p
)
SELECT customer_unique_id,
       MIN(primera_compra) AS primera_compra,
       COUNT(*)            AS n_pedidos,
       -- Volvió: otra compra en un día distinto, dentro de 180 días
       MAX(DATE(fecha_compra) > DATE(primera_compra)
           AND fecha_compra <= primera_compra + INTERVAL 180 DAY)   AS volvio,
       -- Elegible: tuvo al menos 180 días de datos para volver
       MIN(primera_compra) < '2018-03-01'                          AS elegible,
       -- Datos de la primera compra
       MAX(CASE WHEN n_compra = 1 THEN estado_cliente END) AS estado_cliente,
       MAX(CASE WHEN n_compra = 1 THEN valor_total    END) AS valor_primera,
       MAX(CASE WHEN n_compra = 1 THEN valor_flete    END) AS flete_primera,
       MAX(CASE WHEN n_compra = 1 THEN n_items        END) AS items_primera,
       MAX(CASE WHEN n_compra = 1 THEN n_vendedores   END) AS vendedores_primera,
       MAX(CASE WHEN n_compra = 1 THEN nota           END) AS nota_primera,
       MAX(CASE WHEN n_compra = 1 THEN atrasado       END) AS atrasado_primera,
       MAX(CASE WHEN n_compra = 1 THEN dias_atraso    END) AS dias_atraso_primera
FROM compras
GROUP BY customer_unique_id;

-- Verificación: una fila por cliente y tasa de recompra general
SELECT COUNT(*)                           AS clientes,
       COUNT(DISTINCT customer_unique_id) AS clientes_distintos,
       SUM(elegible)                      AS elegibles,
       SUM(volvio AND elegible)           AS volvieron,
       ROUND(AVG(CASE WHEN elegible = 1 THEN volvio END) * 100, 2) AS pct_recompra
FROM v_clientes;

/* Resultado:

   clientes   clientes distintos   elegibles   volvieron   % recompra
     94.703               94.703      56.338       1.121         1,99

   - Una fila por cliente, sin duplicados.
   - Solo el 1,99% de los clientes elegibles vuelve a comprar en 6 meses.
     Es menos que el 3% de recurrentes de la exploración (script 02, 9a),
     que estaba inflado por las compras del mismo día y no consideraba
     el tiempo disponible para volver. */

-- ---------------------------------------------------------------------
-- 3. ¿La nota de la primera compra influye en volver?
-- ---------------------------------------------------------------------

SELECT nota_primera,
       COUNT(*)                    AS clientes,
       SUM(volvio)                 AS volvieron,
       ROUND(AVG(volvio) * 100, 2) AS pct_recompra
FROM v_clientes
WHERE elegible = 1
  AND nota_primera IS NOT NULL
GROUP BY nota_primera
ORDER BY nota_primera;

/* Resultado:

   nota primera compra   clientes   volvieron   % recompra
   1                        6.173         104         1,68
   2                        1.836          28         1,53
   3                        4.864          95         1,95
   4                       11.098         202         1,82
   5                       31.909         686         2,15

   - Los clientes que pusieron 5 estrellas vuelven algo más (2,15% vs
     1,68% con 1 estrella), pero la diferencia es de solo 0,5 puntos.
   - No hay una escalera clara (3 estrellas vuelve más que 4), y el grupo
     de 2 estrellas tiene solo 28 clientes que volvieron.
   - Incluso los clientes satisfechos casi no vuelven: de 31.909 con
     5 estrellas, solo el 2% compró de nuevo. */

-- ---------------------------------------------------------------------
-- 4. ¿Un atraso en la primera compra influye en volver?
-- ---------------------------------------------------------------------
-- Se excluyen los clientes cuya primera compra no tiene fechas válidas
-- (atrasado_primera en NULL).

SELECT atrasado_primera,
       COUNT(*)                    AS clientes,
       SUM(volvio)                 AS volvieron,
       ROUND(AVG(volvio) * 100, 2) AS pct_recompra
FROM v_clientes
WHERE elegible = 1
  AND atrasado_primera IS NOT NULL
GROUP BY atrasado_primera
ORDER BY atrasado_primera;

/* Resultado:

   primera compra   clientes   volvieron   % recompra
   0 (a tiempo)       51.544       1.042         2,02
   1 (atrasada)        3.670          59         1,61

   - Un atraso en la primera compra baja la recompra, pero poco: 0,4
     puntos, con solo 59 clientes atrasados que volvieron.
   - Mismo patrón que la nota: la experiencia de la primera compra
     influye poco en la recompra. */


-- =====================================================================
-- Conclusiones del script 06
-- =====================================================================
/*
   1. La recompra real es de apenas 1,99% en 6 meses, al descontar los
      pedidos del mismo día y dar a todos los clientes el mismo tiempo
      para volver.
   2. La experiencia de la primera compra influye poco: la recompra baja
      solo unas décimas con una mala nota o un atraso. Incluso los
      clientes con 5 estrellas casi no vuelven.
   3. La baja recompra parece un problema estructural, no logístico.
      Hipótesis: Olist conecta a vendedores pequeños con grandes tiendas
      online; el cliente compra en la tienda grande, muchas veces sin saber
      que detrás está Olist. Si vuelve a esa tienda y le compra a otro
      vendedor, esa compra no aparece en estos datos. No se puede confirmar
      con este dataset.
   4. Esta es una conclusión negativa (la entrega NO explica la recompra),
      igual de valiosa: evita invertir en mejorar la logística esperando
      que eso aumente la recompra.

   Pendiente para Python: probar si las diferencias de recompra entre
   grupos (nota y atraso) son estadísticamente significativas.
*/
