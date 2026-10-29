-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 05: Atrasos, reseñas y origen del atraso
-- Motor: MySQL 8
-- =====================================================================
-- Preguntas centrales:
--   - ¿Los atrasos en la entrega bajan la nota de las reseñas?
--   - ¿Qué tan holgada es la fecha prometida y dónde falla?
--   - ¿El atraso se origina en el vendedor o en el transporte?
--
-- Todas las consultas usan v_pedidos (script 03) y solo los pedidos con
-- valido_atrasos = 1 (regla 2): entregados, con fechas completas y en
-- orden lógico. Son 96.018 pedidos.
--
-- Técnica nueva: AVG de una condición. Una condición como (nota <= 2) vale
-- 1 si es verdadera y 0 si es falsa, así que su promedio es la proporción
-- de casos que la cumplen. Lo mismo con las banderas atrasado y vendedor_tarde.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. ¿Los pedidos atrasados tienen peor nota?
-- ---------------------------------------------------------------------
-- El WHERE deja todos los pedidos válidos (atrasados y a tiempo) y el
-- GROUP BY los separa en dos grupos para compararlos.
-- Mala reseña = 1 o 2 estrellas.

SELECT atrasado,
       COUNT(*)                       AS pedidos,
       ROUND(AVG(nota), 2)            AS nota_promedio,
       ROUND(AVG(nota <= 2) * 100, 1) AS pct_malas_resenas
FROM v_pedidos
WHERE valido_atrasos = 1
  AND nota IS NOT NULL
GROUP BY atrasado;

/* Resultado:

   atrasado   pedidos   nota promedio   % malas reseñas
   0 (no)      89.001       4,29              9,2
   1 (sí)       6.375       2,27             62,4

   - Un atraso baja la nota promedio en 2 estrellas (4,29 -> 2,27).
   - Las malas reseñas se multiplican casi 7 veces (9,2% -> 62,4%):
     casi 2 de cada 3 pedidos atrasados reciben 1 o 2 estrellas. */

-- ---------------------------------------------------------------------
-- 2. ¿Importa cuánto se atrasa? Nota por tramo de atraso
-- ---------------------------------------------------------------------
-- dias_atraso: positivo = llegó tarde; 0 o negativo = a tiempo.
-- El CASE revisa las condiciones en orden y se queda con la primera que
-- se cumple, por eso cada tramo solo necesita el límite superior.

SELECT CASE
           WHEN dias_atraso < -7 THEN '1. Más de 7 días antes'
           WHEN dias_atraso <= 0 THEN '2. 0 a 7 días antes'
           WHEN dias_atraso <= 3 THEN '3. 1 a 3 días tarde'
           WHEN dias_atraso <= 7 THEN '4. 4 a 7 días tarde'
           ELSE                       '5. Más de 7 días tarde'
       END AS tramo_atraso,
       COUNT(*)                       AS pedidos,
       ROUND(AVG(nota), 2)            AS nota_promedio,
       ROUND(AVG(nota <= 2) * 100, 1) AS pct_malas_resenas
FROM v_pedidos
WHERE valido_atrasos = 1
  AND nota IS NOT NULL
GROUP BY tramo_atraso
ORDER BY tramo_atraso;

/* Resultado:

   tramo                       pedidos   nota promedio   % malas reseñas
   1. Más de 7 días antes       70.520       4,32              8,9
   2. 0 a 7 días antes          18.481       4,19             10,4
   3. 1 a 3 días tarde           1.850       3,29             32,2
   4. 4 a 7 días tarde           1.746       2,10             67,6
   5. Más de 7 días tarde        2.779       1,70             79,3

   Verificación: los tramos a tiempo suman 89.001 y los atrasados 6.375,
   igual que en la consulta 1 (no se pierden ni duplican pedidos).

   - Llegar antes de lo prometido casi no mejora la nota (4,32 vs 4,19).
     La satisfacción depende de cumplir la promesa, no de llegar rápido.
   - El 79% de los pedidos a tiempo (70.520 de 89.001) llegó con más de una
     semana de anticipación: las fechas prometidas son muy holgadas.
   - Cada día de atraso pesa más: incluso 1 a 3 días triplican las malas
     reseñas (32%), y con más de una semana 4 de cada 5 clientes ponen
     1 o 2 estrellas. */

-- ---------------------------------------------------------------------
-- 3. ¿Qué tan holgada es la promesa en cada estado?
-- ---------------------------------------------------------------------
-- margen_dias = días prometidos - días reales (cuántos días sobran en promedio).

SELECT estado_cliente,
       COUNT(*)                                      AS pedidos,
       ROUND(AVG(dias_prometidos), 1)                AS dias_prometidos_prom,
       ROUND(AVG(dias_entrega), 1)                   AS dias_reales_prom,
       ROUND(AVG(dias_prometidos - dias_entrega), 1) AS margen_dias,
       ROUND(AVG(atrasado) * 100, 1)                 AS pct_atrasados
FROM v_pedidos
WHERE valido_atrasos = 1
GROUP BY estado_cliente
ORDER BY pct_atrasados DESC;

/* Resultado:

   estado   región         pedidos   prometidos   reales   margen   % atrasados
   AL       Nordeste           396      32,5        24,5      8,0       21,5
   MA       Nordeste           710      30,3        21,6      8,7       17,6
   SE       Nordeste           331      30,6        21,4      9,1       15,4
   PI       Nordeste           472      30,0        19,5     10,5       14,0
   CE       Nordeste         1.272      31,2        21,2      9,9       13,8
   RR       Norte               40      45,5        29,9     15,6       12,5
   RJ       Sudeste         12.291      26,3        15,3     11,0       12,2
   BA       Nordeste         3.249      29,4        19,3     10,1       12,2
   PA       Norte              941      37,0        23,8     13,3       11,3
   ES       Sudeste          1.986      25,5        15,8      9,7       10,8
   PB       Nordeste           516      32,9        20,4     12,6       10,5
   TO       Norte              273      29,1        17,7     11,4        9,9
   MS       Centro-Oeste       699      26,0        15,6     10,3        9,7
   PE       Nordeste         1.586      30,9        18,4     12,5        9,6
   RN       Nordeste           470      32,0        19,2     12,8        9,4
   SC       Sur              3.525      25,7        15,0     10,7        8,3
   GO       Centro-Oeste     1.944      27,0        15,6     11,4        6,6
   RS       Sur              5.310      28,4        15,3     13,1        6,1
   MT       Centro-Oeste       882      31,7        18,1     13,6        6,0
   DF       Centro-Oeste     2.071      24,2        12,9     11,3        5,7
   MG       Sudeste         11.293      24,4        12,0     12,5        4,6
   SP       Sudeste         40.334      19,0         8,7     10,3        4,5
   PR       Sur              4.892      24,5        12,0     12,5        4,1
   AC       Norte               80      41,1        21,0     20,1        3,8
   AP       Norte               67      46,2        27,2     19,1        3,0
   RO       Norte              243      38,8        19,4     19,4        2,9
   AM       Norte              145      45,3        26,4     18,9        2,8

   - El atraso no depende de la distancia, sino de qué tan calibrada está
     la promesa:
     * Nordeste (lejos, promesa ajustada): concentra las tasas más altas
       (AL 21,5%, MA 17,6%, SE 15,4%), con solo 8 a 10 días de margen
       sobre promesas de ~30 días.
     * Norte (lo más lejano, promesa muy holgada): casi sin atrasos
       (AM 2,8%, RO 2,9%), con promesas de 41 a 46 días y ~19 de margen.
   - RJ es la excepción: está en el sudeste, junto a SP, pero tiene 12,2%
     de atrasos, casi 3 veces más que SP (4,5%), y es el segundo mercado
     más grande. La distancia no lo explica. Hipótesis: problemas en la
     última milla dentro de la ciudad; no se puede confirmar con estos datos.
   - Incluso en SP sobra margen: se prometen 19 días y llega en 8,7.
   - Oportunidad: redistribuir el margen (prometer menos días donde sobra,
     como SP, y más donde falta, como el Nordeste) permitiría ofrecer
     plazos más atractivos sin aumentar los atrasos.
   - Los estados del Norte tienen pocos pedidos (RR 40, AP 67, AC 80): sus
     porcentajes son señales, no cifras exactas. */

-- ---------------------------------------------------------------------
-- 4. ¿El atraso se origina en el vendedor o en el transporte?
-- ---------------------------------------------------------------------
-- Etapas del pedido y su responsable:
--   compra -> [preparación: VENDEDOR] -> transportista -> [transporte] -> cliente
-- vendedor_tarde = 1 si el vendedor entregó al transportista después de su
-- plazo (shipping_limit_date).

-- 4a. ¿Cuánto aumenta el riesgo de atraso cuando el vendedor no cumple?
SELECT vendedor_tarde,
       COUNT(*)                        AS pedidos,
       ROUND(AVG(dias_preparacion), 1) AS dias_preparacion_prom,
       ROUND(AVG(dias_transporte), 1)  AS dias_transporte_prom,
       ROUND(AVG(atrasado) * 100, 1)   AS pct_atrasados
FROM v_pedidos
WHERE valido_atrasos = 1
GROUP BY vendedor_tarde;

/* Resultado:

   vendedor_tarde        pedidos   preparación   transporte   % atrasados
   0 (cumplió)            87.448      2,6 días      9,3 días        5,4
   1 (fuera de plazo)      8.570      9,5 días      9,9 días       21,1

   - Solo el 8,9% de los pedidos tuvo al vendedor fuera de plazo.
   - Cuando el vendedor no cumple, el pedido tiene 4 veces más probabilidad
     de llegar tarde (21,1% vs 5,4%).
   - El transporte tarda casi lo mismo en ambos casos: la diferencia está
     en la preparación (7 días más) y el transportista no recupera ese
     tiempo perdido. */

-- 4b. De los pedidos atrasados, ¿en cuántos el vendedor cumplió su plazo?
--     Aquí sí se filtra atrasado = 1, porque la pregunta es solo sobre
--     los pedidos que llegaron tarde.
SELECT vendedor_tarde,
       COUNT(*)                                         AS pedidos_atrasados,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) AS pct_de_los_atrasos
FROM v_pedidos
WHERE valido_atrasos = 1
  AND atrasado = 1
GROUP BY vendedor_tarde;

/* Resultado:

   vendedor_tarde        pedidos atrasados   % de los atrasos
   0 (cumplió)                  4.717              72,3
   1 (fuera de plazo)           1.811              27,7

   - El 72,3% de los pedidos atrasados tuvo un vendedor que cumplió su
     plazo: en volumen, la causa principal de los atrasos es el transporte.
   - Las dos lecturas son complementarias:
     * Por pedido, un vendedor fuera de plazo es una señal de alerta fuerte
       (multiplica el riesgo por 4).
     * En el total, como los vendedores casi siempre cumplen, la mayoría de
       los atrasos ocurre en el transporte.
   - Una tasa alta no implica un aporte grande al total: importa también
     el tamaño de cada grupo. */

-- ---------------------------------------------------------------------
-- 5. ¿Recibir el pedido por partes baja la nota?
-- ---------------------------------------------------------------------
-- Los pedidos con varios vendedores casi siempre llegan en paquetes
-- separados (cada vendedor despacha por su cuenta). Para no confundir ese
-- efecto con el de tener más ítems, se separan tres grupos.
-- Solo pedidos a tiempo (atrasado = 0), para que el atraso no influya.
-- El orden de los WHEN importa: un pedido con varios vendedores siempre
-- tiene varios ítems, así que esa condición debe evaluarse primero.

SELECT CASE
           WHEN n_vendedores > 1 THEN '3. Varios vendedores'
           WHEN n_items > 1      THEN '2. Un vendedor, varios ítems'
           ELSE                       '1. Un vendedor, un ítem'
       END AS tipo_pedido,
       COUNT(*)                       AS pedidos,
       ROUND(AVG(nota), 2)            AS nota_promedio,
       ROUND(AVG(nota <= 2) * 100, 1) AS pct_malas_resenas
FROM v_pedidos
WHERE valido_atrasos = 1
  AND atrasado = 0
  AND nota IS NOT NULL
GROUP BY tipo_pedido
ORDER BY tipo_pedido;

/* Resultado (solo pedidos a tiempo):

   tipo de pedido                   pedidos   nota promedio   % malas reseñas
   1. Un vendedor, un ítem           80.022       4,36               7,5
   2. Un vendedor, varios ítems       7.756       3,85              21,0
   3. Varios vendedores               1.223       2,88              46,8

   - Aun llegando a tiempo, los pedidos con varios vendedores tienen peor
     nota que un pedido con 1 a 3 días de atraso (2,88 vs 3,29; ver
     consulta 2). Casi la mitad recibe 1 o 2 estrellas.
   - Varios ítems de un mismo vendedor también bajan la nota (21% de malas
     reseñas, el triple que un solo ítem): más ítems significa más cosas que
     pueden salir mal (un producto faltante, equivocado o que llega después).
   - Precauciones:
     * Hay una sola fecha de entrega por pedido. Si llegan varios paquetes,
       no se sabe a cuál corresponde: algunos pedidos "a tiempo" podrían
       haber tenido un paquete atrasado.
     * Es una relación, no una causa: estos pedidos pueden diferir en otros
       factores (valor, categoría). Se separan los efectos en Python.
   - En volumen son solo el 1,4% de los pedidos, pero la acción es concreta:
     avisar al cliente que el pedido llegará en varios paquetes o
     consolidar los envíos. */

-- ---------------------------------------------------------------------
-- 6. ¿La nota cambia entre reseñas de un mismo pedido?
-- ---------------------------------------------------------------------
-- Se usa order_reviews (no v_resenas), porque la vista ya dejó una sola
-- reseña por pedido y aquí se necesitan todas.
-- Técnicas nuevas:
--   - COUNT(*) OVER (PARTITION BY order_id): cuenta las reseñas del pedido
--     sin juntar las filas; cada reseña queda en su fila con ese total.
--     Así la última reseña es la que tiene n_orden = n_resenas.
--   - MAX(CASE WHEN ...): "gira" los datos. El CASE deja la nota solo en la
--     fila que interesa (primera o última) y NULL en las demás; el MAX con
--     GROUP BY se queda con el único valor no nulo.
-- Al unir con v_pedidos quedan solo los pedidos del período de análisis.

WITH resenas AS (
    -- Paso 1: numerar las reseñas de cada pedido, de la más antigua a la más reciente
    SELECT order_id,
           review_score,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_creation_date, review_answer_timestamp, id) AS n_orden,
           COUNT(*) OVER (PARTITION BY order_id) AS n_resenas
    FROM order_reviews
),
primera_ultima AS (
    -- Paso 2: una fila por pedido con su primera y su última nota
    SELECT order_id,
           MAX(CASE WHEN n_orden = 1         THEN review_score END) AS nota_primera,
           MAX(CASE WHEN n_orden = n_resenas THEN review_score END) AS nota_ultima
    FROM resenas
    WHERE n_resenas > 1
    GROUP BY order_id
)
-- Paso 3: clasificar el cambio y compararlo con las características del pedido
SELECT CASE
           WHEN pu.nota_ultima > pu.nota_primera THEN 'Sube'
           WHEN pu.nota_ultima < pu.nota_primera THEN 'Baja'
           ELSE                                       'Igual'
       END AS cambio,
       COUNT(*)                                AS pedidos,
       ROUND(AVG(pu.nota_primera), 2)          AS nota_primera_prom,
       ROUND(AVG(pu.nota_ultima), 2)           AS nota_ultima_prom,
       ROUND(AVG(p.atrasado) * 100, 1)         AS pct_atrasados,
       ROUND(AVG(p.n_vendedores > 1) * 100, 1) AS pct_varios_vendedores,
       ROUND(AVG(p.n_items > 1) * 100, 1)      AS pct_varios_items
FROM primera_ultima pu
JOIN v_pedidos p ON p.order_id = pu.order_id
GROUP BY cambio;

/* Resultado (pedidos con más de una reseña, dentro del período):

   cambio   pedidos   primera nota   última nota   % atrasados   % varios vendedores   % varios ítems
   Igual        339       4,41           4,41           4,5               0,9                  9,1
   Baja         117       4,52           2,38           8,3               0,0                 14,5
   Sube          83       2,40           4,25           4,9              12,0                 30,1

   - La mayoría (63%) mantiene la misma nota: el sistema vuelve a pedir la
     reseña y el cliente repite su evaluación (ver ejemplos en script 02, 8b).
   - Cuando la nota cambia, cambia fuerte: unas 2 estrellas en cualquier
     dirección. Baja algo más seguido de lo que sube (117 vs 83).
   - Cuando la nota SUBE, el pedido tenía varios vendedores (12% vs 0,9%) o
     varios ítems (30% vs 9%) con mucha más frecuencia. Es consistente con
     un cliente que evalúa mal al recibir una parte del pedido y mejora la
     nota cuando le llega lo que faltaba: la molestia no es la espera, sino
     no recibir todo junto.
   - Cuando la nota BAJA, hay casi el doble de atrasos (8,3% vs 4,5%).
   - Precaución: los grupos son muy pequeños (~10 pedidos detrás de los
     porcentajes de 12% y 8,3%). Es una señal, no una conclusión firme.
     Coincide con la consulta 5, que sí tiene una muestra grande.
   - La regla 3 (usar la reseña más reciente) afecta solo a unos 200
     pedidos: no cambia los resultados generales, pero está justificada
     porque en esos casos la última nota difiere mucho de la primera. */

-- ---------------------------------------------------------------------
-- 7. ¿El flete es más caro en los estados lejanos? ¿Baja la nota?
-- ---------------------------------------------------------------------
-- Hipótesis pendiente del script 04: los pedidos de estados lejanos tienen
-- mayor valor promedio. ¿Es por el flete o por productos más caros?
-- No se filtra por valido_atrasos: el flete y el valor existen en todos los
-- pedidos; ese filtro solo se usa al trabajar con fechas.

SELECT estado_cliente,
       COUNT(*)                                    AS pedidos,
       ROUND(AVG(valor_productos), 1)              AS productos_prom,
       ROUND(AVG(valor_flete), 1)                  AS flete_prom,
       ROUND(SUM(valor_flete) * 100 / SUM(valor_total), 1) AS pct_flete,
       ROUND(AVG(nota), 2)                         AS nota_promedio
FROM v_pedidos
GROUP BY estado_cliente
ORDER BY pct_flete DESC;

/* Resultado:

   estado   región         pedidos   productos   flete   % flete   nota
   RR       Norte               43      177,4     49,2     21,7     3,70
   MA       Nordeste           732      162,0     42,5     20,8     3,78
   RO       Norte              246      187,1     46,3     19,8     4,13
   AM       Norte              147      152,1     37,3     19,7     4,22
   PI       Nordeste           489      176,8     43,1     19,6     3,93
   SE       Nordeste           342      171,4     41,1     19,3     3,83
   TO       Norte              278      177,7     42,1     19,1     4,11
   AC       Norte               81      197,3     45,5     18,7     4,05
   PE       Nordeste         1.636      159,2     36,0     18,5     4,02
   RN       Nordeste           478      172,2     39,1     18,5     4,11
   PB       Nordeste           530      216,6     48,3     18,2     4,02
   PA       Norte              965      184,2     39,9     17,8     3,86
   CE       Nordeste         1.316      170,6     36,5     17,6     3,88
   AP       Norte               68      198,2     41,0     17,1     4,19
   BA       Nordeste         3.340      151,6     29,8     16,5     3,88
   AL       Nordeste           409      196,2     38,8     16,5     3,77
   MT       Centro-Oeste       900      173,3     32,8     15,9     4,11
   GO       Centro-Oeste     1.990      144,2     26,4     15,5     4,07
   RS       Sur              5.395      137,0     24,9     15,4     4,16
   ES       Sudeste          2.014      135,4     24,5     15,3     4,05
   PR       Sur              4.962      136,0     23,5     14,8     4,21
   SC       Sur              3.590      143,8     24,8     14,7     4,10
   MG       Sudeste         11.457      136,9     23,5     14,6     4,17
   RJ       Sudeste         12.654      142,4     24,0     14,4     3,91
   DF       Centro-Oeste     2.114      141,8     23,8     14,4     4,09
   MS       Centro-Oeste       708      164,9     27,0     14,1     4,14
   SP       Sudeste         41.021      125,6     17,4     12,2     4,21

   - El flete pesa casi el doble en los estados lejanos: 12,2% de lo pagado
     en SP (R$ 17 por pedido) contra 17-22% en el Norte y el Nordeste
     (R$ 40-49 por pedido, casi 3 veces más).
   - Los clientes lejanos también compran productos más caros (R$ 126 en SP
     contra R$ 217 en PB). La hipótesis del script 04 se cumple en parte:
     los pedidos lejanos valen más por el flete Y por los productos.
     Hipótesis: con un flete tan caro, solo conviene comprar online
     productos de mayor valor.
   - El flete caro no parece bajar la nota; la nota sigue a los atrasos:
     * Norte: flete muy alto, pero buenas notas (AM 4,22; AP 4,19) y pocos
       atrasos (consulta 3).
     * RJ: de los fletes más bajos (14,4%), pero mala nota (3,91) y muchos
       atrasos.
     * Nordeste: flete alto, notas bajas y también la mayor tasa de atrasos.
     Flete y atraso se mezclan en el Nordeste; se separan en Python. */


-- =====================================================================
-- Conclusiones del script 05
-- =====================================================================
/*
   1. Cumplir la promesa es lo que más importa. Un atraso baja la nota de
      4,29 a 2,27 y multiplica casi por 7 las malas reseñas. Llegar antes de
      lo prometido casi no la mejora.
   2. Las fechas prometidas son muy holgadas: el 79% de los pedidos a tiempo
      llega con más de una semana de anticipación. Por eso solo el 6,8% se
      atrasa.
   3. El atraso no depende de la distancia, sino de cómo está calibrada la
      promesa: el Norte, lejano pero con promesas holgadas, casi no se
      atrasa; el Nordeste, con promesas más ajustadas, concentra los
      atrasos. RJ es una excepción a revisar.
   4. Origen del atraso: un vendedor fuera de plazo multiplica por 4 el
      riesgo, pero el 72% de los pedidos atrasados tuvo un vendedor que
      cumplió. En volumen, el problema principal es el transporte.
   5. Recibir el pedido por partes baja la nota aunque llegue a tiempo
      (varios vendedores: 2,88). Las reseñas que suben de nota coinciden con
      pedidos de varios vendedores o ítems.
   6. El flete caro no parece afectar la nota si el pedido llega a tiempo.

   Pendiente para Python: separar el efecto propio de cada factor (atraso,
   varios vendedores, n° de ítems, flete y región).
*/
