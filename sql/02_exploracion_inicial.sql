-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 02: Etapa 0 - Exploración inicial
-- Motor: MySQL 8
-- =====================================================================
-- Objetivo: entender qué información tiene la base ANTES de analizar,
-- como si nos entregaran una base desconocida y sin documentación.
--
-- Estructura:
--   Parte 1 (consultas 1 a 4):  inventario de tablas, columnas y relaciones
--   Parte 2 (consultas 5 a 12): verificación de hipótesis y calidad de datos
--   Parte 3:                    reglas de limpieza y priorización de preguntas
--
-- Los resultados y su interpretación quedan como comentarios bajo cada consulta.
-- =====================================================================

USE olist;


-- =====================================================================
-- PARTE 1: Inventario de la base
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ¿Qué tablas hay y qué tamaño tienen?
-- ---------------------------------------------------------------------
-- Nota: en InnoDB, table_rows es una ESTIMACIÓN. Sirve para dimensionar;
-- los conteos exactos se verificaron en el script 01.

SELECT table_name                                           AS tabla,
       table_rows                                           AS filas_aprox,
       ROUND((data_length + index_length) / 1024 / 1024, 1) AS tamano_mb
FROM information_schema.tables
WHERE table_schema = 'olist'
ORDER BY table_rows DESC;

-- ---------------------------------------------------------------------
-- 2. ¿Qué columnas tiene cada tabla?
-- ---------------------------------------------------------------------

SELECT table_name       AS tabla,
       ordinal_position AS n,
       column_name      AS columna,
       column_type      AS tipo,
       column_key       AS clave     -- PRI = clave primaria, MUL = índice/relación
FROM information_schema.columns
WHERE table_schema = 'olist'
ORDER BY table_name, ordinal_position;

-- ---------------------------------------------------------------------
-- 3. ¿Cómo se relacionan las tablas? (primera pista: nombres repetidos)
-- ---------------------------------------------------------------------
-- Si una columna con el mismo nombre aparece en varias tablas,
-- probablemente es el vínculo entre ellas.

SELECT column_name AS columna,
       COUNT(*)    AS n_tablas,
       GROUP_CONCAT(table_name ORDER BY table_name SEPARATOR ', ') AS tablas
FROM information_schema.columns
WHERE table_schema = 'olist'
  AND column_name <> 'id'          -- ids autoincrementales propios, no son relaciones
GROUP BY column_name
HAVING COUNT(*) > 1
ORDER BY n_tablas DESC, columna;

/* Resultado:
   order_id               4 tablas: order_items, order_payments, order_reviews, orders
   customer_id            2 tablas: customers, orders
   product_category_name  2 tablas: category_translation, products
   product_id             2 tablas: order_items, products
   seller_id              2 tablas: order_items, sellers

   Interpretación: orders es la tabla central. order_id la conecta con ítems,
   pagos y reseñas, y de ahí salen ramas hacia clientes, productos y vendedores.

   customers ── orders ──┬── order_items ──┬── products ── category_translation
                         ├── order_payments └── sellers
                         └── order_reviews
   geolocation ··· (se une por código postal con customers y sellers)

   Limitación del método: solo detecta columnas que se llaman igual. La relación
   por código postal con geolocation no aparece porque las columnas tienen
   nombres distintos (customer_zip_code_prefix, geolocation_zip_code_prefix). */

-- ---------------------------------------------------------------------
-- 4. Cardinalidad de las columnas tipo "id"
-- ---------------------------------------------------------------------
-- Si valores_distintos = filas, la columna identifica cada fila (clave).
-- Si valores_distintos < filas, el valor se repite: hay que entender por qué.

SELECT 'customers'   AS tabla, 'customer_id'        AS columna, COUNT(*) AS filas, COUNT(DISTINCT customer_id)        AS valores_distintos FROM customers
UNION ALL SELECT 'customers',      'customer_unique_id',          COUNT(*), COUNT(DISTINCT customer_unique_id)          FROM customers
UNION ALL SELECT 'orders',         'order_id',                    COUNT(*), COUNT(DISTINCT order_id)                    FROM orders
UNION ALL SELECT 'orders',         'customer_id',                 COUNT(*), COUNT(DISTINCT customer_id)                 FROM orders
UNION ALL SELECT 'order_items',    'order_id',                    COUNT(*), COUNT(DISTINCT order_id)                    FROM order_items
UNION ALL SELECT 'order_items',    'product_id',                  COUNT(*), COUNT(DISTINCT product_id)                  FROM order_items
UNION ALL SELECT 'order_items',    'seller_id',                   COUNT(*), COUNT(DISTINCT seller_id)                   FROM order_items
UNION ALL SELECT 'order_payments', 'order_id',                    COUNT(*), COUNT(DISTINCT order_id)                    FROM order_payments
UNION ALL SELECT 'order_reviews',  'review_id',                   COUNT(*), COUNT(DISTINCT review_id)                   FROM order_reviews
UNION ALL SELECT 'order_reviews',  'order_id',                    COUNT(*), COUNT(DISTINCT order_id)                    FROM order_reviews
UNION ALL SELECT 'products',       'product_id',                  COUNT(*), COUNT(DISTINCT product_id)                  FROM products
UNION ALL SELECT 'sellers',        'seller_id',                   COUNT(*), COUNT(DISTINCT seller_id)                   FROM sellers
UNION ALL SELECT 'geolocation',    'geolocation_zip_code_prefix', COUNT(*), COUNT(DISTINCT geolocation_zip_code_prefix) FROM geolocation;

/* Resultado e interpretación:

   - customers: 99.441 customer_id, pero solo 96.096 customer_unique_id.
     La tabla customers tiene las mismas filas que orders: el sistema crea un
     customer_id nuevo en cada compra. 3.345 registros son personas que
     volvieron a comprar. El cliente real es customer_unique_id (se verifica en 9).

   - order_items: 112.650 filas para 98.666 pedidos.
     Hay pedidos con varios ítems, y 775 pedidos SIN ítems (99.441 - 98.666).
     -> Hipótesis: pedidos que no se concretaron (se verifica en 6).

   - product_id y seller_id: todos los productos (32.951) y vendedores (3.095)
     aparecen en order_items. El dataset solo incluye productos y vendedores
     que vendieron algo: es una base construida a partir de las ventas, no el
     catálogo completo.

   - order_payments: 103.886 filas para 99.440 pedidos.
     Algunos pedidos tienen varios pagos y 1 pedido no tiene pago (se verifica en 7).

   - order_reviews: review_id NO es único (98.410 distintos de 99.224) y hay
     98.673 pedidos con reseña. Hay reseñas asociadas a varios pedidos, pedidos
     con más de una reseña y 768 pedidos sin reseña (se verifica en 8).
     -> Riesgo: unir pedidos con reseñas sin cuidado duplica pedidos y sesga
        el análisis de atraso vs nota.

   - geolocation: 1.000.163 filas para 19.015 códigos postales (~50 por código).
     -> Riesgo: unir directo por código postal multiplica cada cliente ~50 veces.
        Habría que agregar por código antes de unir. */


-- =====================================================================
-- PARTE 2: Verificación de hipótesis y calidad de datos
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5. Estados de pedido y período cubierto
-- ---------------------------------------------------------------------

-- 5a. ¿Qué estados existen y cuántos pedidos hay en cada uno?
SELECT order_status, COUNT(*) AS pedidos
FROM orders
GROUP BY order_status
ORDER BY pedidos DESC;

/* Resultado: delivered 96.478 | shipped 1.107 | canceled 625 | unavailable 609 |
              invoiced 314 | processing 301 | created 5 | approved 2
   El 97% de los pedidos está entregado. */

-- 5b. ¿Qué período cubren los datos y cuántos pedidos hay por mes?
--     (para detectar meses con muy pocos datos en los extremos)
SELECT DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS mes,
       COUNT(*)                                       AS pedidos
FROM orders
GROUP BY mes
ORDER BY mes;

/* Resultado: meses con muy pocos pedidos en los extremos: 2016-09 (4),
   2016-12 (1), 2018-09 (16) y 2018-10 (4). Los pedidos crecen desde
   principios de 2017 hasta agosto de 2018.

   La caída desde septiembre de 2018 NO es una baja real de ventas: ahí se
   corta la extracción de datos y los pedidos más recientes seguían en curso.
   Con 2016 pasa algo similar: la plataforma recién estaba partiendo.
   Graficar sin filtrar mostraría un "desplome" falso.

   Decisión: analizar de enero 2017 a agosto 2018. */

-- ---------------------------------------------------------------------
-- 6. Hipótesis: los 775 pedidos sin ítems son pedidos que no se concretaron
-- ---------------------------------------------------------------------

SELECT o.order_status, COUNT(*) AS pedidos_sin_items
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY pedidos_sin_items DESC;

/* Resultado: unavailable 603 | canceled 164 | created 5 | invoiced 2 | shipped 1

   Se confirma: 603 de los 609 pedidos "unavailable" no tienen ítems, o sea,
   la venta nunca se concretó. Como las ventas se calculan desde order_items,
   estos pedidos no afectan el análisis. */

-- ---------------------------------------------------------------------
-- 7. Pagos: el pedido sin pago y los pedidos con varios pagos
-- ---------------------------------------------------------------------

-- 7a. ¿Cuál es el pedido sin pago y qué tiene?
SELECT o.order_id, o.order_status, o.order_purchase_timestamp,
       COUNT(oi.order_item_id) AS items,
       SUM(oi.price)           AS total_productos
FROM orders o
LEFT JOIN order_payments p ON p.order_id = o.order_id
LEFT JOIN order_items oi   ON oi.order_id = o.order_id
WHERE p.order_id IS NULL
GROUP BY o.order_id, o.order_status, o.order_purchase_timestamp;

/* Resultado: bfbd0f9bdef84302105ad712db648a6c | delivered | 2016-09-15 | 3 ítems | 134,97
   Caso aislado de 2016 (error de registro). Queda fuera del período de análisis. */

-- 7b. ¿Cuántos pagos tienen los pedidos?
SELECT n_pagos, COUNT(*) AS pedidos
FROM (SELECT order_id, COUNT(*) AS n_pagos
      FROM order_payments
      GROUP BY order_id) AS t
GROUP BY n_pagos
ORDER BY n_pagos;

/* Resultado (n° de pagos: pedidos):
   1: 96.479 | 2: 2.382 | 3: 301 | 4: 108 | 5: 52 | 6: 36 | 7: 28 | 8: 11 |
   9: 9 | 10: 5 | 11: 8 | 12: 8 | 13: 3 | 14: 2 | 15: 2 | 19: 2 | 21: 1 |
   22: 1 | 26: 1 | 29: 1

   El 97% de los pedidos se paga en un solo pago; 2.961 tienen dos o más. */

-- 7c. En los pedidos con más de un pago, ¿qué medios de pago se usan?
SELECT payment_type, COUNT(*) AS pagos
FROM order_payments
WHERE order_id IN (SELECT order_id
                   FROM order_payments
                   GROUP BY order_id
                   HAVING COUNT(*) > 1)
GROUP BY payment_type
ORDER BY pagos DESC;

/* Resultado: voucher 4.581 | credit_card 2.823 | debit_card 3

   Los pedidos con muchos pagos (hasta 29) se explican por los vouchers: cada
   cupón o gift card queda registrado como un pago aparte, normalmente
   combinado con tarjeta de crédito.
   Decisión: el total pagado de un pedido es SUM(payment_value). */

-- ---------------------------------------------------------------------
-- 8. Reseñas: pedidos con varias reseñas, reseñas repetidas y sin reseña
-- ---------------------------------------------------------------------

-- 8a. ¿Cuántas reseñas tienen los pedidos?
SELECT n_resenas, COUNT(*) AS pedidos
FROM (SELECT order_id, COUNT(*) AS n_resenas
      FROM order_reviews
      GROUP BY order_id) AS t
GROUP BY n_resenas
ORDER BY n_resenas;

/* Resultado: 1 reseña: 98.126 | 2 reseñas: 543 | 3 reseñas: 4
   Solo 547 pedidos (0,55%) tienen más de una reseña. */

-- 8b. Ejemplos de pedidos con más de una reseña: ¿qué cambia entre ellas?
SELECT r.order_id, r.review_id, r.review_score,
       r.review_creation_date, r.review_comment_message
FROM order_reviews r
WHERE r.order_id IN (SELECT order_id
                     FROM order_reviews
                     GROUP BY order_id
                     HAVING COUNT(*) > 1)
ORDER BY r.order_id, r.review_creation_date
LIMIT 20;

/* Observaciones: la mayoría de las reseñas adicionales no tiene comentario.
   Aparecen dos patrones:

   - Comentarios casi idénticos en el mismo pedido (02e0b688...: "Gostei e
     entregou rapidinho" / "Gostei chegou rapidinho"). Sugiere que el sistema
     vuelve a pedir la reseña, posiblemente al cambiar el estado del envío.
   - Una reseña por cada entrega (03c939fd...: el cliente compró 3 productos
     iguales, llegaron por separado y le cobraron 3 despachos).

   Con los datos no se puede confirmar cuál es la causa; queda como hipótesis.
   El segundo ejemplo ilustra justo la pregunta del proyecto: una mala
   experiencia de entrega que se refleja en la reseña.

   Decisión: usar una reseña por pedido, la más reciente, porque refleja la
   experiencia final del cliente. */

-- 8c. Hipótesis: un review_id repetido corresponde a la MISMA persona
--     que hizo varios pedidos y los evaluó una sola vez.
--     Si clientes_distintos = 1 en todos los casos, se confirma.
SELECT clientes_distintos, COUNT(*) AS review_ids_repetidos
FROM (SELECT r.review_id,
             COUNT(DISTINCT c.customer_unique_id) AS clientes_distintos
      FROM order_reviews r
      JOIN orders o    ON o.order_id = r.order_id
      JOIN customers c ON c.customer_id = o.customer_id
      GROUP BY r.review_id
      HAVING COUNT(*) > 1) AS t
GROUP BY clientes_distintos;

/* Resultado: 1 cliente distinto en los 789 review_id repetidos.
   Se confirma: es una misma persona que hizo varios pedidos juntos y los
   evaluó con una sola reseña. */

-- 8d. ¿Qué estado tienen los pedidos sin reseña?
SELECT o.order_status, COUNT(*) AS pedidos_sin_resena
FROM orders o
LEFT JOIN order_reviews r ON r.order_id = o.order_id
WHERE r.order_id IS NULL
GROUP BY o.order_status
ORDER BY pedidos_sin_resena DESC;

/* Resultado: delivered 646 | shipped 75 | canceled 20 | unavailable 14 |
              processing 6 | invoiced 5 | created 2   (total 768)
   Son pocos (menos del 1% de los entregados). El análisis de satisfacción
   se hace solo sobre pedidos con reseña. */

-- ---------------------------------------------------------------------
-- 9. Clientes: confirmar que customer_unique_id es la persona real
-- ---------------------------------------------------------------------

-- 9a. ¿Cuántos pedidos hace cada persona?
SELECT n_pedidos, COUNT(*) AS clientes
FROM (SELECT customer_unique_id, COUNT(*) AS n_pedidos
      FROM customers
      GROUP BY customer_unique_id) AS t
GROUP BY n_pedidos
ORDER BY n_pedidos;

/* Resultado: 1 pedido: 93.099 | 2: 2.745 | 3: 203 | 4: 30 | 5: 8 | 6: 6 |
              7: 3 | 9: 1 | 17: 1

   El 96,9% de los clientes compra una sola vez; solo 2.997 vuelven a comprar.
   La recompra es el gran problema del negocio. Además, en un RFM la
   frecuencia casi no variaría entre clientes. */

-- 9b. El cliente con más pedidos: ¿sus customer_id cambian en cada compra?
WITH top_cliente AS (
    SELECT customer_unique_id
    FROM customers
    GROUP BY customer_unique_id
    ORDER BY COUNT(*) DESC
    LIMIT 1
)
SELECT c.customer_unique_id, c.customer_id, c.customer_city,
       c.customer_zip_code_prefix, o.order_id,
       o.order_purchase_timestamp, o.order_status
FROM top_cliente t
JOIN customers c ON c.customer_unique_id = t.customer_unique_id
JOIN orders o    ON o.customer_id = c.customer_id
ORDER BY o.order_purchase_timestamp;

/* Resultado: el customer_id cambia en cada compra; se mantienen el
   customer_unique_id y el código postal. Se confirma que customer_unique_id
   identifica a la persona.

   Hipótesis inicial: el customer_id nuevo serviría para guardar la dirección
   de cada compra. En este cliente el código postal no cambió, pero es un solo
   caso (quizás no se cambió de casa). Se revisa para todos en 9c. */

-- 9c. ¿Los clientes recurrentes registran distintos códigos postales?
SELECT COUNT(*)        AS clientes_recurrentes,
       SUM(n_zip > 1)  AS con_mas_de_un_codigo_postal
FROM (SELECT customer_unique_id,
             COUNT(DISTINCT customer_zip_code_prefix) AS n_zip
      FROM customers
      GROUP BY customer_unique_id
      HAVING COUNT(*) > 1) AS t;

/* Resultado: 250 de los 2.997 clientes recurrentes (8,3%) registran más de
   un código postal.

   La hipótesis queda parcialmente respaldada: algunas personas sí compran
   con direcciones distintas, y generar un customer_id por pedido permite
   guardar la dirección de cada compra. Con los datos no se puede confirmar
   que esa sea la razón del diseño, pero es consistente con lo observado.
   Para el análisis no cambia nada: el cliente sigue siendo customer_unique_id. */

-- ---------------------------------------------------------------------
-- 10. Productos: categorías vacías y sin traducción
-- ---------------------------------------------------------------------

-- 10a. ¿Cuántos productos no tienen categoría?
SELECT COUNT(*) AS productos_sin_categoria
FROM products
WHERE product_category_name IS NULL;

/* Resultado: 610 productos sin categoría. */

-- 10b. ¿Qué categorías no tienen traducción al inglés?
SELECT DISTINCT p.product_category_name
FROM products p
LEFT JOIN category_translation t
       ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;

/* Resultado: pc_gamer | portateis_cozinha_e_preparadores_de_alimentos

   Decisión: los productos sin categoría quedan como "sin_categoria" para no
   perder esas ventas, y las 2 traducciones faltantes se agregan a mano. */

-- ---------------------------------------------------------------------
-- 11. Códigos postales: ¿todos tienen coordenadas en geolocation?
-- ---------------------------------------------------------------------

SELECT 'clientes' AS grupo,
       COUNT(*)   AS sin_coordenadas
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM geolocation g
                  WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)
UNION ALL
SELECT 'vendedores',
       COUNT(*)
FROM sellers s
WHERE NOT EXISTS (SELECT 1 FROM geolocation g
                  WHERE g.geolocation_zip_code_prefix = s.seller_zip_code_prefix);

/* Resultado: 278 clientes y 7 vendedores sin coordenadas.
   Decisión: el análisis geográfico se hace por estado, que está completo en
   las tablas de clientes y vendedores. */

-- ---------------------------------------------------------------------
-- 12. Coherencia de fechas (clave para el análisis de atrasos)
-- ---------------------------------------------------------------------

SELECT
    SUM(order_status = 'delivered' AND order_delivered_customer_date IS NULL)
        AS entregados_sin_fecha_entrega,
    SUM(order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL)
        AS no_entregados_con_fecha_entrega,
    SUM(order_delivered_customer_date < order_purchase_timestamp)
        AS entrega_antes_de_compra,
    SUM(order_delivered_carrier_date < order_purchase_timestamp)
        AS despacho_antes_de_compra,
    SUM(order_delivered_customer_date < order_delivered_carrier_date)
        AS entrega_antes_de_despacho
FROM orders;

/* Resultado:
   entregados_sin_fecha_entrega     8
   no_entregados_con_fecha_entrega  6
   entrega_antes_de_compra          0
   despacho_antes_de_compra       166
   entrega_antes_de_despacho       23

   Hay fechas imposibles (despachos antes de la compra, entregas antes del
   despacho). Son errores de registro, pero suman unos 200 de 96 mil pedidos.
   Decisión: excluirlos del análisis de atrasos y mencionarlo en las limitaciones. */


-- =====================================================================
-- PARTE 3: Conclusiones de la exploración
-- =====================================================================

/* ---------------------------------------------------------------------
   Reglas de limpieza (se implementan como vistas en el script 03)
   ---------------------------------------------------------------------
   1. Período de análisis: enero 2017 a agosto 2018.
   2. Análisis de atrasos: solo pedidos entregados con fechas completas y coherentes.
   3. Una reseña por pedido (la más reciente).
   4. El cliente es customer_unique_id.
   5. Productos sin categoría -> "sin_categoria"; agregar las 2 traducciones faltantes.
   6. Análisis geográfico por estado (no por coordenadas).
   7. Ventas desde order_items (precio + flete); pagos solo para analizar medios de pago.

   ---------------------------------------------------------------------
   Priorización de preguntas de negocio
   ---------------------------------------------------------------------
   Criterios:
   - Impacto en el negocio: si la respuesta lleva a una acción concreta.
   - Calidad de los datos: si la exploración mostró que alcanzan para responderla.
   - Diferenciación: si aporta una mirada logística, poco común en análisis de e-commerce.
   - Técnicas: si permite aplicar JOIN, CTE y funciones de ventana en SQL,
     segmentación en Python y un modelo de varias tablas en Power BI.

   CENTRALES
   - ¿Los atrasos bajan la nota de las reseñas?
     Incluye qué tan exacta es la fecha prometida y si entregar antes mejora la nota.
   - ¿El atraso se origina en el vendedor o en el transporte?
     shipping_limit_date permite separar responsabilidades. Incluye en qué
     estados y rutas (vendedor -> cliente) se concentran los atrasos.
   - ¿Qué distingue a los clientes que vuelven a comprar?
     Reformulada: era "¿qué clientes retener?", pero con 97% de compra única
     el problema real es por qué no vuelven. Los ~3.000 clientes recurrentes
     permiten comparar su primera experiencia con la del resto.
   - Segmentación de vendedores con k-means (ver decisión abajo).

   CONTEXTO
   - ¿Cómo evolucionan las ventas y qué categorías y regiones concentran?
     No es la pregunta principal, pero el dashboard necesita esa base.

   OPCIONAL
   - ¿El flete alto baja la nota? Interesante (ver ejemplo en 8b), pero secundaria.

   DESCARTADAS
   - Medios de pago y cuotas: poca relación con la historia del proyecto;
     como mucho, un indicador en el dashboard.
   - Análisis del texto de los comentarios: en portugués, la mayoría vacíos
     y requiere otra técnica (procesamiento de texto).
   - Mapas con coordenadas y distancias exactas: faltan coordenadas y
     geolocation está muy duplicada. Se hace por estado.

   ---------------------------------------------------------------------
   Decisión: ¿a quién segmentar?
   ---------------------------------------------------------------------
   Segmentar clientes con RFM aporta poco, porque la frecuencia es casi
   siempre 1 (consulta 9a). Se segmentan los VENDEDORES: Olist es un
   marketplace con 3.095 vendedores, que sí varían en volumen, tasa de atraso,
   tiempo de despacho y nota promedio. Además conecta con la pregunta del
   origen del atraso y lleva a una acción concreta: a qué vendedores apoyar
   o exigir. */
