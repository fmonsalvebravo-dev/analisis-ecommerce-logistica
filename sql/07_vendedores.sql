-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 07: Vendedores - tabla de características para la segmentación
-- Motor: MySQL 8
-- =====================================================================
-- Objetivo: construir una fila por vendedor con sus características de
-- volumen y de calidad, que se usará en Python para segmentar a los
-- vendedores con k-means.
--
-- Dos problemas a resolver antes de calcular:
--   1. Vendedores con muy pocos pedidos: sus tasas son ruido (1 pedido
--      atrasado = 100% de atrasos). Se fija un mínimo de pedidos.
--   2. Pedidos con varios vendedores: si llegó atrasado, no se sabe de
--      cuál fue la responsabilidad. Las métricas de calidad se calculan
--      solo con pedidos de un vendedor (98,6% de los pedidos).
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. ¿Cuántos pedidos tiene cada vendedor?
-- ---------------------------------------------------------------------
-- COUNT(DISTINCT order_id): v_items tiene una fila por producto; un pedido
-- con 3 productos del mismo vendedor se contaría 3 veces con COUNT(*).

WITH por_vendedor AS (
    SELECT seller_id,
           COUNT(DISTINCT order_id) AS n_pedidos,
           SUM(precio + flete)      AS ventas
    FROM v_items
    GROUP BY seller_id
)
SELECT CASE
           WHEN n_pedidos = 1    THEN '1. 1 pedido'
           WHEN n_pedidos <= 9   THEN '2. 2 a 9 pedidos'
           WHEN n_pedidos <= 49  THEN '3. 10 a 49 pedidos'
           WHEN n_pedidos <= 199 THEN '4. 50 a 199 pedidos'
           ELSE                       '5. 200 o más pedidos'
       END AS tramo,
       COUNT(*)                                               AS vendedores,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)       AS pct_vendedores,
       ROUND(SUM(ventas) * 100 / SUM(SUM(ventas)) OVER (), 1) AS pct_ventas
FROM por_vendedor
GROUP BY tramo
ORDER BY tramo;

/* Resultado (3.029 vendedores con ventas en el período):

   tramo                    vendedores   % vendedores   % ventas
   1. 1 pedido                    545        18,0          0,9
   2. 2 a 9 pedidos             1.226        40,5          8,0
   3. 10 a 49 pedidos             831        27,4         22,5
   4. 50 a 199 pedidos            336        11,1         30,9
   5. 200 o más pedidos            91         3,0         37,7

   - El 58,5% de los vendedores tiene menos de 10 pedidos y genera menos
     del 9% de las ventas.
   - 91 vendedores (3%) generan el 37,7% de las ventas, y los de 50 o más
     pedidos (14%) casi el 70%. A diferencia de las categorías, aquí hay un
     Pareto fuerte: esos ~430 vendedores son los que más importa cuidar.

   Decisión: la segmentación usa los vendedores con 10 pedidos o más.
   Son 1.258 vendedores (41,5%) que generan el 91% de las ventas. Se evita
   el ruido de las tasas con muy pocos pedidos, aunque con 10 pedidos un
   solo atraso sigue siendo un 10% (limitación). */

-- ---------------------------------------------------------------------
-- 2. Vista v_vendedores: una fila por vendedor
-- ---------------------------------------------------------------------
-- - volumen: usa TODOS los pedidos del vendedor.
-- - calidad: usa solo pedidos con un vendedor (n_vendedores = 1), para
--   atribuir bien la responsabilidad de atrasos y notas.
-- - SELECT DISTINCT order_id, seller_id: pasa de una fila por producto a
--   una fila por pedido y vendedor, para no contar un pedido varias veces.
-- - LEFT JOIN final: un vendedor que solo vendió en pedidos compartidos no
--   tiene fila en "calidad"; con LEFT JOIN no se pierde (queda en NULL).

CREATE OR REPLACE VIEW v_vendedores AS
WITH volumen AS (
    SELECT seller_id,
           MIN(estado_vendedor)                           AS estado_vendedor,
           COUNT(DISTINCT order_id)                       AS n_pedidos,
           SUM(precio + flete)                            AS ventas,
           COUNT(DISTINCT categoria)                      AS n_categorias,
           DATEDIFF(MAX(fecha_compra), MIN(fecha_compra)) AS dias_activo
    FROM v_items
    GROUP BY seller_id
),
pedido_vendedor AS (
    SELECT DISTINCT order_id, seller_id
    FROM v_items
),
calidad AS (
    SELECT pv.seller_id,
           COUNT(*)                              AS pedidos_un_vendedor,
           ROUND(AVG(p.dias_preparacion), 1)     AS dias_preparacion_prom,
           ROUND(AVG(p.vendedor_tarde) * 100, 1) AS pct_fuera_plazo,
           ROUND(AVG(p.atrasado) * 100, 1)       AS pct_atrasados,
           ROUND(AVG(p.nota), 2)                 AS nota_promedio,
           ROUND(AVG(p.nota <= 2) * 100, 1)      AS pct_malas_resenas
    FROM pedido_vendedor pv
    JOIN v_pedidos p ON p.order_id = pv.order_id
    WHERE p.n_vendedores = 1
    GROUP BY pv.seller_id
)
SELECT v.seller_id,
       v.estado_vendedor,
       v.n_pedidos,
       ROUND(v.ventas, 2)               AS ventas,
       ROUND(v.ventas / v.n_pedidos, 2) AS ticket_promedio,
       v.n_categorias,
       v.dias_activo,
       c.pedidos_un_vendedor,
       c.dias_preparacion_prom,
       c.pct_fuera_plazo,
       c.pct_atrasados,
       c.nota_promedio,
       c.pct_malas_resenas,
       (v.n_pedidos >= 10)              AS apto_segmentacion
FROM volumen v
LEFT JOIN calidad c ON c.seller_id = v.seller_id;

-- Verificación
SELECT COUNT(*)               AS vendedores,
       SUM(apto_segmentacion) AS aptos,
       ROUND(SUM(ventas), 2)  AS ventas_total,
       ROUND(AVG(CASE WHEN apto_segmentacion = 1 THEN pct_atrasados END), 1) AS pct_atrasados_prom_aptos,
       ROUND(AVG(CASE WHEN apto_segmentacion = 1 THEN nota_promedio END), 2) AS nota_prom_aptos
FROM v_vendedores;

/* Resultado:

   vendedores   aptos   ventas total     % atrasados (aptos)   nota (aptos)
        3.029   1.258   15.683.706,74           6,8                4,16

   - Mismos vendedores y aptos que la consulta 1.
   - Las ventas son exactamente las de los scripts 03 y 04: la vista no
     duplica ni pierde datos.
   - Los vendedores aptos tienen atrasos y nota similares al total del
     negocio (6,8% y 4,12), porque concentran el 91% de las ventas. */

-- ---------------------------------------------------------------------
-- 3. ¿Los vendedores se diferencian realmente?
-- ---------------------------------------------------------------------
-- Antes de segmentar, se verifica que haya diferencias reales entre
-- vendedores. Dos métricas distintas:
--   pct_fuera_plazo: % de pedidos que el VENDEDOR entregó al transportista
--                    después de su plazo (solo mide al vendedor).
--   pct_atrasados:   % de pedidos que llegaron al CLIENTE después de la
--                    fecha prometida (resultado final: vendedor + transporte).
-- Aquí AVG promedia vendedores, no pedidos: cada vendedor pesa lo mismo,
-- que es lo que interesa para comparar tipos de vendedor.

SELECT CASE
           WHEN pct_fuera_plazo = 0   THEN '1. Siempre cumple'
           WHEN pct_fuera_plazo <= 10 THEN '2. Hasta 10% fuera de plazo'
           WHEN pct_fuera_plazo <= 25 THEN '3. 10 a 25% fuera de plazo'
           ELSE                            '4. Más de 25% fuera de plazo'
       END AS tramo_cumplimiento,
       COUNT(*)                             AS vendedores,
       SUM(n_pedidos)                       AS pedidos,
       ROUND(AVG(dias_preparacion_prom), 1) AS dias_preparacion,
       ROUND(AVG(pct_atrasados), 1)         AS pct_atrasados,
       ROUND(AVG(nota_promedio), 2)         AS nota
FROM v_vendedores
WHERE apto_segmentacion = 1
  AND pct_fuera_plazo IS NOT NULL
GROUP BY tramo_cumplimiento
ORDER BY tramo_cumplimiento;

/* Resultado (vendedores aptos):

   cumplimiento                     vendedores   pedidos   preparación   % atrasados   nota
   1. Siempre cumple                       372    10.121     1,9 días        4,9       4,29
   2. Hasta 10% fuera de plazo             497    56.599     2,6 días        6,0       4,22
   3. 10 a 25% fuera de plazo              242    18.053     4,2 días        7,8       4,09
   4. Más de 25% fuera de plazo            147     8.490     6,9 días       12,7       3,77

   - El 30% de los vendedores aptos siempre cumple su plazo, y casi 7 de
     cada 10 se pasan como mucho en el 10% de sus pedidos.
   - Hay una escalera clara: a menor cumplimiento, preparación más lenta,
     más atrasos y peor nota. Los 147 vendedores que más fallan preparan
     en 6,9 días (vs 1,9) y tienen 2,6 veces más atrasos.
   - El grupo que siempre cumple igual tiene 4,9% de atrasos: como el
     vendedor nunca falló, es atraso puro del transporte (línea base).
   - Matiz: "siempre cumple" no implica ser el mejor vendedor. Ese grupo
     promedia 27 pedidos por vendedor, contra 114 del grupo 2: con pocos
     pedidos hay menos oportunidades de fallar. Los grandes vendedores
     están casi todos en el grupo 2. Por eso la segmentación combina
     varias características y no solo una.
   - Las diferencias son reales: la segmentación con k-means tiene sentido. */


-- =====================================================================
-- Conclusiones del script 07
-- =====================================================================
/*
   1. Los vendedores de Olist son muy desiguales: el 3% genera el 38% de las
      ventas y casi 6 de cada 10 tienen menos de 10 pedidos.
   2. La vista v_vendedores tiene una fila por vendedor con características
      de volumen (pedidos, ventas, ticket, categorías, días activo) y de
      calidad (preparación, cumplimiento de plazo, atrasos, nota y malas
      reseñas), calculadas solo con pedidos de un vendedor.
   3. Para la segmentación se usan los 1.258 vendedores con 10 o más
      pedidos (apto_segmentacion = 1), que generan el 91% de las ventas.
   4. El cumplimiento del plazo diferencia claramente a los vendedores en
      atrasos y nota, lo que confirma que hay segmentos que encontrar.

   Siguiente paso (Python): leer v_vendedores con SQLAlchemy, escalar las
   variables, elegir el número de grupos (codo y silueta), aplicar k-means,
   nombrar cada segmento y guardar el resultado en MySQL para Power BI.
*/
