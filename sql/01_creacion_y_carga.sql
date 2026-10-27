-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 01: creación de la base de datos y carga de los CSV
-- Motor: MySQL 8
-- =====================================================================
-- Requisitos:
--   - Habilitar LOAD DATA LOCAL INFILE en el servidor (primera línea del
--     script) y en la conexión de Workbench: Edit Connection > Advanced >
--     Others: OPT_LOCAL_INFILE=1
--   - Ajustar la ruta de los CSV a la carpeta local donde se descargaron
--     desde Kaggle (usar "/" en vez de "\").
--
-- Decisiones de diseño:
--   - Se mantienen los nombres de columnas originales del dataset.
--   - Los ids son hashes de 32 caracteres -> CHAR(32).
--   - Códigos postales como texto, para no perder los ceros a la izquierda.
--   - Montos en DECIMAL para evitar errores de redondeo.
--   - Las celdas vacías se cargan como NULL (NULLIF).
--   - Se limpia un posible "\r" al final de cada línea (TRIM), por si el
--     archivo tiene saltos de línea de Windows.
--   - order_reviews y geolocation no tienen una clave natural confiable,
--     por eso llevan un id autoincremental. Los duplicados se revisan en
--     la etapa de exploración (script 02).
--   - Se usa LOAD DATA en vez del asistente de importación de Workbench,
--     que sería muy lento para geolocation (~1 millón de filas).
-- =====================================================================

SET GLOBAL local_infile = 1;

DROP DATABASE IF EXISTS olist;   -- Permite volver a correr el script desde cero
CREATE DATABASE olist CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE olist;

-- ---------------------------------------------------------------------
-- 1. Creación de tablas (primero las tablas "padre", luego las "hijas")
-- ---------------------------------------------------------------------

CREATE TABLE customers (
    customer_id              CHAR(32)     NOT NULL,
    customer_unique_id       CHAR(32)     NOT NULL,   -- el cliente real
    customer_zip_code_prefix VARCHAR(5),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2),
    PRIMARY KEY (customer_id),
    INDEX idx_customer_unique (customer_unique_id)
);

CREATE TABLE sellers (
    seller_id              CHAR(32)     NOT NULL,
    seller_zip_code_prefix VARCHAR(5),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2),
    PRIMARY KEY (seller_id)
);

CREATE TABLE products (
    product_id                 CHAR(32)    NOT NULL,
    product_category_name      VARCHAR(60),
    product_name_lenght        INT,        -- "lenght" viene así en el dataset original
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT,
    PRIMARY KEY (product_id)
);

CREATE TABLE category_translation (
    product_category_name         VARCHAR(60) NOT NULL,
    product_category_name_english VARCHAR(60),
    PRIMARY KEY (product_category_name)
);

CREATE TABLE orders (
    order_id                      CHAR(32)    NOT NULL,
    customer_id                   CHAR(32)    NOT NULL,
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME,
    order_approved_at             DATETIME,
    order_delivered_carrier_date  DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    PRIMARY KEY (order_id),
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE order_items (
    order_id            CHAR(32)      NOT NULL,
    order_item_id       INT           NOT NULL,   -- n° de ítem dentro del pedido
    product_id          CHAR(32)      NOT NULL,
    seller_id           CHAR(32)      NOT NULL,
    shipping_limit_date DATETIME,                 -- plazo del vendedor para entregar al transportista
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    FOREIGN KEY (product_id) REFERENCES products (product_id),
    FOREIGN KEY (seller_id)  REFERENCES sellers (seller_id)
);

CREATE TABLE order_payments (
    order_id             CHAR(32)      NOT NULL,
    payment_sequential   INT           NOT NULL,
    payment_type         VARCHAR(20),
    payment_installments INT,
    payment_value        DECIMAL(10,2),
    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

CREATE TABLE order_reviews (
    id                      INT          NOT NULL AUTO_INCREMENT,
    review_id               CHAR(32)     NOT NULL,
    order_id                CHAR(32)     NOT NULL,
    review_score            TINYINT,
    review_comment_title    VARCHAR(255),
    review_comment_message  TEXT,
    review_creation_date    DATETIME,
    review_answer_timestamp DATETIME,
    PRIMARY KEY (id),
    INDEX idx_review_id (review_id),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

CREATE TABLE geolocation (
    id                          INT          NOT NULL AUTO_INCREMENT,
    geolocation_zip_code_prefix VARCHAR(5),
    geolocation_lat             DOUBLE,
    geolocation_lng             DOUBLE,
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2),
    PRIMARY KEY (id),
    INDEX idx_geo_zip (geolocation_zip_code_prefix)
);

-- ---------------------------------------------------------------------
-- 2. Carga de los CSV (mismo orden: padres primero)
-- ---------------------------------------------------------------------

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, @state)
SET customer_state = TRIM(TRAILING '\r' FROM @state);

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, @state)
SET seller_state = TRIM(TRAILING '\r' FROM @state);

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, @cat, @name_len, @desc_len, @photos, @weight, @length, @height, @width)
SET product_category_name      = NULLIF(@cat, ''),
    product_name_lenght        = NULLIF(@name_len, ''),
    product_description_lenght = NULLIF(@desc_len, ''),
    product_photos_qty         = NULLIF(@photos, ''),
    product_weight_g           = NULLIF(@weight, ''),
    product_length_cm          = NULLIF(@length, ''),
    product_height_cm          = NULLIF(@height, ''),
    product_width_cm           = NULLIF(TRIM(TRAILING '\r' FROM @width), '');

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/product_category_name_translation.csv'
INTO TABLE category_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_category_name, @eng)
SET product_category_name_english = TRIM(TRAILING '\r' FROM @eng);

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, @purchase, @approved, @carrier, @delivered, @estimated)
SET order_purchase_timestamp      = NULLIF(@purchase, ''),
    order_approved_at             = NULLIF(@approved, ''),
    order_delivered_carrier_date  = NULLIF(@carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered, ''),
    order_estimated_delivery_date = NULLIF(TRIM(TRAILING '\r' FROM @estimated), '');

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, @freight)
SET freight_value = TRIM(TRAILING '\r' FROM @freight);

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, @value)
SET payment_value = TRIM(TRAILING '\r' FROM @value);

LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(review_id, order_id, review_score, @title, @message, @created, @answered)
SET review_comment_title    = NULLIF(@title, ''),
    review_comment_message  = NULLIF(@message, ''),
    review_creation_date    = NULLIF(@created, ''),
    review_answer_timestamp = NULLIF(TRIM(TRAILING '\r' FROM @answered), '');

-- La más pesada (~1 millón de filas): puede tardar uno o dos minutos
LOAD DATA LOCAL INFILE 'RUTA/A/TU/CARPETA/olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, @state)
SET geolocation_state = TRIM(TRAILING '\r' FROM @state);

-- ---------------------------------------------------------------------
-- 3. Verificación: filas cargadas vs filas esperadas según Kaggle
-- ---------------------------------------------------------------------

SELECT 'customers'            AS tabla, COUNT(*) AS filas,   99441 AS esperado FROM customers
UNION ALL SELECT 'sellers',              COUNT(*),    3095 FROM sellers
UNION ALL SELECT 'products',             COUNT(*),   32951 FROM products
UNION ALL SELECT 'category_translation', COUNT(*),      71 FROM category_translation
UNION ALL SELECT 'orders',               COUNT(*),   99441 FROM orders
UNION ALL SELECT 'order_items',          COUNT(*),  112650 FROM order_items
UNION ALL SELECT 'order_payments',       COUNT(*),  103886 FROM order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*),   99224 FROM order_reviews
UNION ALL SELECT 'geolocation',          COUNT(*), 1000163 FROM geolocation;

-- Resultado: las 9 tablas cargaron completas, con los mismos conteos de Kaggle.
