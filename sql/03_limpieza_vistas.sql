-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 03: Reglas de limpieza convertidas en vistas
-- Motor: MySQL 8
-- =====================================================================
-- Objetivo: aplicar UNA sola vez las reglas de limpieza definidas en la
-- exploración (script 02), para que todos los análisis posteriores partan
-- de datos limpios sin repetir filtros en cada consulta.
--
-- Vistas que se crean:
--   v_resenas   -> una reseña por pedido (la más reciente)
--   v_productos -> productos con categoría en inglés y sin vacíos
--   v_pedidos   -> UNA FILA POR PEDIDO: cliente, montos, nota y tiempos
--                  de entrega. Es la vista central del análisis.
--   v_items     -> una fila por producto vendido, con categoría y vendedor
--
-- Reglas aplicadas (numeración del script 02):
--   1. Período: enero 2017 a agosto 2018                       -> v_pedidos
--   2. Atrasos solo con pedidos entregados y fechas coherentes -> v_pedidos (valido_atrasos)
--   3. Una reseña por pedido, la más reciente                  -> v_resenas
--   4. El cliente es customer_unique_id                        -> v_pedidos
--   5. "sin_categoria" y traducciones faltantes                -> sección 1 y v_productos
--   6. Análisis geográfico por estado                          -> v_pedidos y v_items
--   7. Ventas desde order_items (precio + flete)               -> v_pedidos y v_items
--
-- Decisión adicional: se excluyen los pedidos cancelados ("canceled") y no
-- disponibles ("unavailable"), porque no son ventas concretadas.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. Completar las 2 traducciones de categoría faltantes (regla 5)
-- ---------------------------------------------------------------------
-- INSERT IGNORE permite volver a correr el script sin error de duplicado.

INSERT IGNORE INTO category_translation (product_category_name, product_category_name_english)
VALUES ('pc_gamer',                                       'pc_gamer'),
       ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers');

-- ---------------------------------------------------------------------
-- 2. v_resenas: una reseña por pedido (regla 3)
-- ---------------------------------------------------------------------
-- ROW_NUMBER numera las reseñas de cada pedido de la más reciente a la más
-- antigua; se conserva solo la número 1. Los desempates usan la fecha de
-- respuesta y, al final, el id de carga.

CREATE OR REPLACE VIEW v_resenas AS
SELECT order_id,
       review_score         AS nota,
       tiene_comentario,
       review_creation_date AS fecha_resena
FROM (
    SELECT order_id,
           review_score,
           (review_comment_message IS NOT NULL) AS tiene_comentario,
           review_creation_date,
           ROW_NUMBER() OVER (
               PARTITION BY order_id
               ORDER BY review_creation_date DESC,
                        review_answer_timestamp DESC,
                        id DESC
           ) AS n_resena
    FROM order_reviews
) AS r
WHERE n_resena = 1;

-- ---------------------------------------------------------------------
-- 3. v_productos: categoría en inglés y sin vacíos (regla 5)
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_productos AS
SELECT p.product_id,
       COALESCE(t.product_category_name_english,
                p.product_category_name,
                'sin_categoria')                                   AS categoria,
       p.product_weight_g                                          AS peso_g,
       p.product_length_cm * p.product_height_cm * p.product_width_cm AS volumen_cm3
FROM products p
LEFT JOIN category_translation t
       ON t.product_category_name = p.product_category_name;

-- ---------------------------------------------------------------------
-- 4. v_pedidos: vista central, una fila por pedido (reglas 1, 2, 4, 6, 7)
-- ---------------------------------------------------------------------
-- Se construye en dos pasos:
--   a) Subconsulta "base": une pedido, cliente, totales de sus ítems y
--      reseña, aplica el período y marca si el pedido sirve para analizar
--      atrasos (valido_atrasos).
--   b) Consulta exterior: calcula los tiempos de entrega SOLO para los
--      pedidos válidos; en el resto quedan en NULL. Así ningún análisis
--      de atrasos puede incluir por error fechas incompletas o imposibles.
--
-- Cómo leer los tiempos (en días, con un decimal):
--   dias_preparacion : compra -> entrega al transportista (responsabilidad del vendedor)
--   dias_transporte  : entrega al transportista -> entrega al cliente
--   dias_entrega     : compra -> entrega al cliente (total)
--   dias_prometidos  : compra -> fecha estimada que se le informó al cliente
--   dias_atraso      : días entre la fecha estimada y la entrega real.
--                      Positivo = llegó tarde; 0 o negativo = a tiempo
--                      (negativo = llegó antes de lo prometido)
--   vendedor_tarde   : 1 si el vendedor entregó al transportista después de
--                      su plazo (shipping_limit_date). En pedidos con varios
--                      vendedores se usa el plazo más tardío.
--
-- estado_vendedor: en pedidos con más de un vendedor (n_vendedores > 1) se
-- muestra solo uno de sus estados. Para analizar rutas vendedor -> cliente
-- conviene usar pedidos con un solo vendedor, o la vista v_items.

CREATE OR REPLACE VIEW v_pedidos AS
SELECT
    b.order_id,
    b.customer_unique_id,
    b.estado_cliente,
    b.estado_vendedor,
    b.n_vendedores,
    b.estado_pedido,
    b.fecha_compra,
    DATE_FORMAT(b.fecha_compra, '%Y-%m')                                AS mes_compra,
    b.n_items,
    b.valor_productos,
    b.valor_flete,
    b.valor_productos + b.valor_flete                                   AS valor_total,
    b.nota,
    b.tiene_comentario,
    b.valido_atrasos,
    IF(b.valido_atrasos, ROUND(TIMESTAMPDIFF(HOUR, b.fecha_compra,   b.fecha_despacho) / 24, 1), NULL) AS dias_preparacion,
    IF(b.valido_atrasos, ROUND(TIMESTAMPDIFF(HOUR, b.fecha_despacho, b.fecha_entrega)  / 24, 1), NULL) AS dias_transporte,
    IF(b.valido_atrasos, ROUND(TIMESTAMPDIFF(HOUR, b.fecha_compra,   b.fecha_entrega)  / 24, 1), NULL) AS dias_entrega,
    IF(b.valido_atrasos, ROUND(TIMESTAMPDIFF(HOUR, b.fecha_compra,   b.fecha_estimada) / 24, 1), NULL) AS dias_prometidos,
    IF(b.valido_atrasos, DATEDIFF(b.fecha_entrega, b.fecha_estimada), NULL)                            AS dias_atraso,
    IF(b.valido_atrasos, DATE(b.fecha_entrega) > DATE(b.fecha_estimada), NULL)                         AS atrasado,
    IF(b.valido_atrasos, b.fecha_despacho > b.plazo_despacho, NULL)                                    AS vendedor_tarde
FROM (
    SELECT
        o.order_id,
        c.customer_unique_id,
        c.customer_state                    AS estado_cliente,
        i.estado_vendedor,
        i.n_vendedores,
        o.order_status                      AS estado_pedido,
        o.order_purchase_timestamp          AS fecha_compra,
        o.order_delivered_carrier_date      AS fecha_despacho,
        o.order_delivered_customer_date     AS fecha_entrega,
        o.order_estimated_delivery_date     AS fecha_estimada,
        i.plazo_despacho,
        i.n_items,
        i.valor_productos,
        i.valor_flete,
        r.nota,
        r.tiene_comentario,
        -- Regla 2: entregado, con fechas completas y en orden lógico
        (o.order_status = 'delivered'
         AND o.order_delivered_carrier_date  IS NOT NULL
         AND o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
         AND o.order_delivered_carrier_date  >= o.order_purchase_timestamp
         AND o.order_delivered_customer_date >= o.order_delivered_carrier_date) AS valido_atrasos
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    -- Totales por pedido desde order_items (regla 7). El JOIN (no LEFT JOIN)
    -- deja fuera los pedidos sin ítems, que no son ventas.
    JOIN (
        SELECT oi.order_id,
               COUNT(*)                   AS n_items,
               COUNT(DISTINCT oi.seller_id) AS n_vendedores,
               SUM(oi.price)              AS valor_productos,
               SUM(oi.freight_value)      AS valor_flete,
               MAX(oi.shipping_limit_date) AS plazo_despacho,
               MIN(s.seller_state)        AS estado_vendedor
        FROM order_items oi
        JOIN sellers s ON s.seller_id = oi.seller_id
        GROUP BY oi.order_id
    ) AS i ON i.order_id = o.order_id
    LEFT JOIN v_resenas r ON r.order_id = o.order_id
    -- Regla 1: período de análisis
    WHERE o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    -- Decisión adicional: solo ventas concretadas
      AND o.order_status NOT IN ('canceled', 'unavailable')
) AS b;

-- ---------------------------------------------------------------------
-- 5. v_items: una fila por producto vendido
-- ---------------------------------------------------------------------
-- Se une con v_pedidos para heredar sus filtros (período y estados).
-- Sirve para analizar categorías, vendedores y rutas vendedor -> cliente.

CREATE OR REPLACE VIEW v_items AS
SELECT oi.order_id,
       oi.order_item_id,
       oi.product_id,
       pr.categoria,
       oi.seller_id,
       s.seller_state          AS estado_vendedor,
       p.estado_cliente,
       p.customer_unique_id,
       p.fecha_compra,
       p.mes_compra,
       oi.shipping_limit_date  AS plazo_despacho,
       oi.price                AS precio,
       oi.freight_value        AS flete
FROM order_items oi
JOIN v_pedidos   p  ON p.order_id    = oi.order_id
JOIN v_productos pr ON pr.product_id = oi.product_id
JOIN sellers     s  ON s.seller_id   = oi.seller_id;


-- =====================================================================
-- 6. Verificación de las vistas
-- =====================================================================

-- 6a. v_resenas debe tener exactamente una fila por pedido.
--     Esperado: filas = pedidos_distintos = 98.673
SELECT COUNT(*)                 AS filas,
       COUNT(DISTINCT order_id) AS pedidos_distintos
FROM v_resenas;

/* Resultado: 98.673 filas = 98.673 pedidos distintos. Correcto. */

-- 6b. Resumen de v_pedidos: tamaño, período y pedidos válidos para atrasos.
--     (AVG ignora los NULL, por lo que el % de atrasados se calcula solo
--      sobre los pedidos válidos)
SELECT COUNT(*)                      AS pedidos,
       COUNT(DISTINCT order_id)      AS pedidos_distintos,
       MIN(fecha_compra)             AS primera_compra,
       MAX(fecha_compra)             AS ultima_compra,
       SUM(valido_atrasos)           AS validos_para_atrasos,
       ROUND(AVG(atrasado) * 100, 1) AS pct_atrasados,
       ROUND(AVG(nota), 2)           AS nota_promedio,
       SUM(nota IS NULL)             AS pedidos_sin_resena
FROM v_pedidos;

/* Resultado:
   pedidos               97.905 (sin duplicados)
   período               2017-01-05 a 2018-08-29
   válidos para atrasos  96.018 (98% del total)
   % atrasados            6,8%
   nota promedio          4,12
   pedidos sin reseña       727

   Primera señal para el análisis: solo el 6,8% llega atrasado. Queda por
   revisar (script 05) si esto se debe a una buena operación o a fechas
   prometidas holgadas. */

-- 6c. Las ventas deben cuadrar entre v_pedidos y v_items.
SELECT (SELECT SUM(valor_total)    FROM v_pedidos) AS ventas_v_pedidos,
       (SELECT SUM(precio + flete) FROM v_items)   AS ventas_v_items;

/* Resultado: R$ 15.683.706,74 en ambas vistas. Las ventas cuadran. */

-- 6d. Categorías: los productos sin categoría y las 2 traducciones nuevas.
SELECT categoria, COUNT(*) AS items_vendidos
FROM v_items
WHERE categoria IN ('sin_categoria', 'pc_gamer', 'portable_kitchen_and_food_preparers')
GROUP BY categoria;

/* Resultado: sin_categoria 1.587 | portable_kitchen_and_food_preparers 14 | pc_gamer 8
   Los productos sin categoría se conservan y las traducciones nuevas funcionan. */
