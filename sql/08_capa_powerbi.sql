-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 08: Capa de datos para Power BI
-- Motor: MySQL 8
-- =====================================================================
-- Objetivo: dejar en MySQL las tablas y vistas que carga Power BI, con
-- las columnas ya calculadas según las mismas definiciones del análisis.
-- Así Power BI solo carga y relaciona, y no se repite lógica en dos lugares.
--
-- Modelo en estrella:
--   v_pbi_pedidos   (hechos, una fila por pedido)
--   v_items         (hechos, una fila por producto vendido; script 03)
--   v_pbi_vendedores(dimensión, una fila por vendedor, con su segmento)
--   v_clientes      (dimensión, una fila por cliente; script 06)
--   dim_estado      (dimensión, una fila por estado)
--   escenarios_resena (resultado del modelo de Python, notebook 01)
--   + calendario creado en DAX dentro de Power BI
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. dim_estado: nombre completo y región de cada estado
-- ---------------------------------------------------------------------
-- ubicacion_mapa incluye el país para que el mapa de Power BI no confunda
-- siglas como "SP" o "MA" con lugares de otros países.

DROP TABLE IF EXISTS dim_estado;
CREATE TABLE dim_estado (
    estado          CHAR(2)      NOT NULL,
    nombre_estado   VARCHAR(40)  NOT NULL,
    region          VARCHAR(15)  NOT NULL,
    ubicacion_mapa  VARCHAR(60)  NOT NULL,
    PRIMARY KEY (estado)
);

INSERT INTO dim_estado (estado, nombre_estado, region, ubicacion_mapa) VALUES
('SP', 'São Paulo',           'Sudeste',      'São Paulo, Brazil'),
('RJ', 'Rio de Janeiro',      'Sudeste',      'Rio de Janeiro, Brazil'),
('MG', 'Minas Gerais',        'Sudeste',      'Minas Gerais, Brazil'),
('ES', 'Espírito Santo',      'Sudeste',      'Espírito Santo, Brazil'),
('PR', 'Paraná',              'Sur',          'Paraná, Brazil'),
('SC', 'Santa Catarina',      'Sur',          'Santa Catarina, Brazil'),
('RS', 'Rio Grande do Sul',   'Sur',          'Rio Grande do Sul, Brazil'),
('DF', 'Distrito Federal',    'Centro-Oeste', 'Distrito Federal, Brazil'),
('GO', 'Goiás',               'Centro-Oeste', 'Goiás, Brazil'),
('MT', 'Mato Grosso',         'Centro-Oeste', 'Mato Grosso, Brazil'),
('MS', 'Mato Grosso do Sul',  'Centro-Oeste', 'Mato Grosso do Sul, Brazil'),
('BA', 'Bahia',               'Nordeste',     'Bahia, Brazil'),
('PE', 'Pernambuco',          'Nordeste',     'Pernambuco, Brazil'),
('CE', 'Ceará',               'Nordeste',     'Ceará, Brazil'),
('AL', 'Alagoas',             'Nordeste',     'Alagoas, Brazil'),
('SE', 'Sergipe',             'Nordeste',     'Sergipe, Brazil'),
('MA', 'Maranhão',            'Nordeste',     'Maranhão, Brazil'),
('PI', 'Piauí',               'Nordeste',     'Piauí, Brazil'),
('PB', 'Paraíba',             'Nordeste',     'Paraíba, Brazil'),
('RN', 'Rio Grande do Norte', 'Nordeste',     'Rio Grande do Norte, Brazil'),
('AM', 'Amazonas',            'Norte',        'Amazonas, Brazil'),
('PA', 'Pará',                'Norte',        'Pará, Brazil'),
('AC', 'Acre',                'Norte',        'Acre, Brazil'),
('AP', 'Amapá',               'Norte',        'Amapá, Brazil'),
('RO', 'Rondônia',            'Norte',        'Rondônia, Brazil'),
('RR', 'Roraima',             'Norte',        'Roraima, Brazil'),
('TO', 'Tocantins',           'Norte',        'Tocantins, Brazil');

-- ---------------------------------------------------------------------
-- 2. v_pbi_pedidos: v_pedidos + columnas para graficar
-- ---------------------------------------------------------------------
-- fecha:        fecha de compra sin hora, para relacionar con el calendario.
-- tramo_atraso: mismos tramos del script 05 (NULL si no hay fechas válidas).
-- tramo_orden:  número para ordenar los tramos en Power BI
--               (Ordenar por columna), sin mostrarlo en la etiqueta.
-- tipo_pedido:  mismos grupos del script 05 y del notebook 01.

CREATE OR REPLACE VIEW v_pbi_pedidos AS
SELECT p.*,
       DATE(p.fecha_compra) AS fecha,
       CASE
           WHEN p.valido_atrasos = 0 THEN NULL
           WHEN p.dias_atraso < -7   THEN 'Más de 7 días antes'
           WHEN p.dias_atraso <= 0   THEN '0 a 7 días antes'
           WHEN p.dias_atraso <= 3   THEN '1 a 3 días tarde'
           WHEN p.dias_atraso <= 7   THEN '4 a 7 días tarde'
           ELSE                           'Más de 7 días tarde'
       END AS tramo_atraso,
       CASE
           WHEN p.valido_atrasos = 0 THEN NULL
           WHEN p.dias_atraso < -7   THEN 1
           WHEN p.dias_atraso <= 0   THEN 2
           WHEN p.dias_atraso <= 3   THEN 3
           WHEN p.dias_atraso <= 7   THEN 4
           ELSE                           5
       END AS tramo_orden,
       CASE
           WHEN p.n_vendedores > 1 THEN 'Varios vendedores'
           WHEN p.n_items > 1      THEN 'Un vendedor, varios ítems'
           ELSE                         'Un vendedor, un ítem'
       END AS tipo_pedido
FROM v_pedidos p;

-- ---------------------------------------------------------------------
-- 3. v_pbi_vendedores: vendedores con su segmento
-- ---------------------------------------------------------------------
-- Los vendedores con menos de 10 pedidos no se segmentaron (script 07);
-- quedan como "No segmentado" para no perderlos en los filtros.
-- segmento_orden: orden de importancia para el negocio (Ordenar por columna).
-- accion:         acción sugerida para cada segmento (notebook 03).

CREATE OR REPLACE VIEW v_pbi_vendedores AS
SELECT v.*,
       COALESCE(s.segmento, 'No segmentado') AS segmento,
       CASE s.segmento
           WHEN 'Grandes vendedores'  THEN 1
           WHEN 'Alto valor'          THEN 2
           WHEN 'Pequeños confiables' THEN 3
           WHEN 'Servicio irregular'  THEN 4
           WHEN 'Servicio crítico'    THEN 5
           ELSE                            6
       END AS segmento_orden,
       CASE s.segmento
           WHEN 'Grandes vendedores'  THEN 'Cuidarlos: sostienen la mayor parte del negocio'
           WHEN 'Alto valor'          THEN 'Mantener el servicio en productos de precio alto'
           WHEN 'Pequeños confiables' THEN 'Ayudarlos a crecer: ya tienen el mejor servicio'
           WHEN 'Servicio irregular'  THEN 'Monitorear y acompañar'
           WHEN 'Servicio crítico'    THEN 'Exigir mejoras o suspender'
           ELSE                            'Menos de 10 pedidos: sin segmentar'
       END AS accion
FROM v_vendedores v
LEFT JOIN segmento_vendedores s ON s.seller_id = v.seller_id;

-- ---------------------------------------------------------------------
-- 4. Verificación
-- ---------------------------------------------------------------------

SELECT 'dim_estado'       AS objeto, COUNT(*) AS filas FROM dim_estado
UNION ALL SELECT 'v_pbi_pedidos',    COUNT(*) FROM v_pbi_pedidos
UNION ALL SELECT 'v_pbi_vendedores', COUNT(*) FROM v_pbi_vendedores;

-- Esperado: dim_estado 27 | v_pbi_pedidos 97.905 | v_pbi_vendedores 3.029

SELECT segmento, COUNT(*) AS vendedores
FROM v_pbi_vendedores
GROUP BY segmento
ORDER BY vendedores DESC;

-- Esperado: No segmentado 1.771 | Pequeños confiables 416 |
-- Grandes vendedores 306 | Servicio irregular 263 | Alto valor 206 |
-- Servicio crítico 67

-- Nota: la tabla escenarios_resena se crea desde python/01_satisfaccion.ipynb.

-- ---------------------------------------------------------------------
-- 5. Categorías en español
-- ---------------------------------------------------------------------
-- categoria_es: traducción manual de las categorías (en inglés en el dataset).
-- v_pbi_categorias: una fila por categoría con su nombre en español. Si una
-- categoría no tiene traducción, conserva el nombre original (COALESCE),
-- así ninguna queda fuera del modelo.

DROP TABLE IF EXISTS categoria_es;
CREATE TABLE categoria_es (
    categoria    VARCHAR(60)  NOT NULL,
    categoria_es VARCHAR(80)  NOT NULL,
    PRIMARY KEY (categoria)
);

INSERT INTO categoria_es (categoria, categoria_es) VALUES
('agro_industry_and_commerce',              'Agroindustria y comercio'),
('air_conditioning',                        'Aire acondicionado'),
('art',                                     'Arte'),
('arts_and_craftmanship',                   'Artesanía'),
('audio',                                   'Audio'),
('auto',                                    'Accesorios para auto'),
('baby',                                    'Bebés'),
('bed_bath_table',                          'Cama, mesa y baño'),
('books_general_interest',                  'Libros de interés general'),
('books_imported',                          'Libros importados'),
('books_technical',                         'Libros técnicos'),
('cds_dvds_musicals',                       'CD y DVD musicales'),
('christmas_supplies',                      'Artículos navideños'),
('cine_photo',                              'Cine y fotografía'),
('computers',                               'Computadores'),
('computers_accessories',                   'Accesorios de computación'),
('consoles_games',                          'Consolas y videojuegos'),
('construction_tools_construction',         'Herramientas de construcción'),
('construction_tools_lights',               'Iluminación'),
('construction_tools_safety',               'Seguridad para construcción'),
('cool_stuff',                              'Productos novedosos'),
('costruction_tools_garden',                'Herramientas de jardín y construcción'),
('costruction_tools_tools',                 'Herramientas'),
('diapers_and_hygiene',                     'Pañales e higiene'),
('drinks',                                  'Bebidas'),
('dvds_blu_ray',                            'DVD y Blu-ray'),
('electronics',                             'Electrónica'),
('fashio_female_clothing',                  'Ropa de mujer'),
('fashion_bags_accessories',                'Bolsos y accesorios'),
('fashion_childrens_clothes',               'Ropa infantil'),
('fashion_male_clothing',                   'Ropa de hombre'),
('fashion_shoes',                           'Calzado'),
('fashion_sport',                           'Ropa deportiva'),
('fashion_underwear_beach',                 'Ropa interior y de playa'),
('fixed_telephony',                         'Telefonía fija'),
('flowers',                                 'Flores'),
('food',                                    'Alimentos'),
('food_drink',                              'Alimentos y bebidas'),
('furniture_bedroom',                       'Muebles de dormitorio'),
('furniture_decor',                         'Muebles y decoración'),
('furniture_living_room',                   'Muebles de living'),
('furniture_mattress_and_upholstery',       'Colchones y tapicería'),
('garden_tools',                            'Herramientas de jardín'),
('health_beauty',                           'Salud y belleza'),
('home_appliances',                         'Electrodomésticos'),
('home_appliances_2',                       'Electrodomésticos (otros)'),
('home_comfort_2',                          'Confort del hogar (otros)'),
('home_confort',                            'Confort del hogar'),
('home_construction',                       'Construcción del hogar'),
('housewares',                              'Artículos para el hogar'),
('industry_commerce_and_business',          'Industria y comercio'),
('kitchen_dining_laundry_garden_furniture', 'Muebles de cocina, comedor y jardín'),
('la_cuisine',                              'Cocina gourmet'),
('luggage_accessories',                     'Maletas y accesorios de viaje'),
('market_place',                            'Marketplace'),
('music',                                   'Música'),
('musical_instruments',                     'Instrumentos musicales'),
('office_furniture',                        'Muebles de oficina'),
('party_supplies',                          'Artículos de fiesta'),
('pc_gamer',                                'PC gamer'),
('perfumery',                               'Perfumería'),
('pet_shop',                                'Mascotas'),
('portable_kitchen_and_food_preparers',     'Cocina portátil y procesadores de alimentos'),
('security_and_services',                   'Seguridad y servicios'),
('signaling_and_security',                  'Señalización y seguridad'),
('sin_categoria',                           'Sin categoría'),
('small_appliances',                        'Pequeños electrodomésticos'),
('small_appliances_home_oven_and_coffee',   'Hornos y cafeteras'),
('sports_leisure',                          'Deportes y ocio'),
('stationery',                              'Papelería'),
('tablets_printing_image',                  'Tablets e impresión'),
('telephony',                               'Telefonía'),
('toys',                                    'Juguetes'),
('watches_gifts',                           'Relojes y regalos');

CREATE OR REPLACE VIEW v_pbi_categorias AS
SELECT DISTINCT p.categoria,
       COALESCE(t.categoria_es, p.categoria) AS categoria_es
FROM v_productos p
LEFT JOIN categoria_es t ON t.categoria = p.categoria;

-- Verificación: categorías sin traducción (esperado: ninguna)
SELECT categoria
FROM v_pbi_categorias
WHERE categoria = categoria_es;
