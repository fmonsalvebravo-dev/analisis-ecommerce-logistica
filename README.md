# Análisis de e-commerce y logística (Olist)

¿Los atrasos en la entrega bajan la satisfacción de los clientes? ¿El atraso se origina en el vendedor o en el transporte? ¿Por qué casi ningún cliente vuelve a comprar? Este proyecto analiza unos 100 mil pedidos reales de un marketplace brasileño en cuatro etapas: **exploración inicial** de una base desconocida, **SQL** para limpiar los datos y responder las preguntas de negocio, **Python** para separar el efecto de cada factor y segmentar a los vendedores, y **Power BI** para presentar los resultados.

> **Proyecto en desarrollo.** Etapa 0 (carga y exploración) completa. Las siguientes etapas se irán agregando a medida que avance el análisis.

## Hallazgos principales

*Pendiente: se completa al terminar el análisis.*

## Estructura del repositorio

```
analisis-ecommerce-logistica/
├── README.md
├── sql/
│   ├── 01_creacion_y_carga.sql       Creación de la base y carga de los 9 CSV
│   ├── 02_exploracion_inicial.sql    Inventario, verificación de hipótesis y reglas de limpieza
│   ├── 03_limpieza_vistas.sql        (pendiente) Reglas de limpieza como vistas
│   ├── 04_ventas.sql                 (pendiente) Tendencias, categorías y regiones
│   ├── 05_atrasos_y_resenas.sql      (pendiente) Atrasos, notas y origen del atraso
│   ├── 06_recompra.sql               (pendiente) Clientes que vuelven a comprar
│   └── 07_vendedores.sql             (pendiente) Características de vendedores para la segmentación
├── python/                           (pendiente)
└── powerbi/                          (pendiente)
```

## Datos

- **Fuente:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), disponible en Kaggle. Son **datos reales y anonimizados** de Olist, un marketplace que conecta a pequeños vendedores con grandes tiendas online de Brasil.
- **Tamaño:** unos 100 mil pedidos entre 2016 y 2018, repartidos en 9 tablas relacionadas.
- Los CSV no se incluyen en el repositorio por su tamaño (unos 120 MB). Se descargan desde el link de Kaggle.

## Herramientas

- **MySQL 8** y MySQL Workbench
- **Python 3.11:** pandas, SQLAlchemy, scikit-learn (Jupyter Notebook en VS Code)
- **Power BI Desktop:** DAX, Power Query

## Cómo reproducir el proyecto

1. Descargar los 9 CSV desde Kaggle.
2. En MySQL Workbench, habilitar la carga de archivos locales: *Edit Connection > Advanced > Others:* `OPT_LOCAL_INFILE=1`.
3. En `sql/01_creacion_y_carga.sql`, reemplazar `RUTA/A/TU/CARPETA/` por la carpeta donde quedaron los CSV y ejecutar el script. Al final muestra una verificación de filas cargadas.
4. Ejecutar los demás scripts en orden.

## Etapa 0: Entendimiento de los datos

Antes de analizar, la base se exploró **como si fuera desconocida y sin documentación**, que es la situación habitual al recibir una base en una empresa. El proceso tuvo tres pasos: inventario de lo que contiene, verificación de hipótesis con consultas y priorización de las preguntas a responder.

Las consultas completas, con sus resultados comentados, están en [`sql/02_exploracion_inicial.sql`](sql/02_exploracion_inicial.sql).

### Inventario

El inventario se obtuvo consultando la propia base (`information_schema`), sin revisar los archivos uno por uno.

| Tabla | Filas | Contenido |
|---|---:|---|
| `orders` | 99.441 | Pedidos: estado y fechas de compra, aprobación, entrega al transportista, entrega al cliente y entrega estimada |
| `order_items` | 112.650 | Productos de cada pedido: precio, flete, vendedor y plazo del vendedor para despachar |
| `order_payments` | 103.886 | Pagos: medio de pago, cuotas y monto |
| `order_reviews` | 99.224 | Reseñas: nota de 1 a 5 y comentario |
| `customers` | 99.441 | Clientes: código postal, ciudad y estado |
| `sellers` | 3.095 | Vendedores: código postal, ciudad y estado |
| `products` | 32.951 | Productos: categoría, peso y medidas |
| `category_translation` | 71 | Traducción de las categorías del portugués al inglés |
| `geolocation` | 1.000.163 | Coordenadas por código postal |

Las columnas con el mismo nombre en distintas tablas mostraron cómo se relacionan. `orders` es la tabla central:

```
customers ── orders ──┬── order_items ──┬── products ── category_translation
                      ├── order_payments └── sellers
                      └── order_reviews
geolocation ··· (se une por código postal con customers y sellers)
```

### Inferir el significado de las columnas a partir de los datos

Comparar el total de filas con los valores distintos de cada columna (cardinalidad) permitió deducir cómo funciona la base. Por ejemplo, la tabla de clientes tiene exactamente las mismas filas que la de pedidos: **el sistema crea un `customer_id` nuevo en cada compra**, y la persona real se identifica con `customer_unique_id` (96.096 personas distintas). Revisando a los clientes que compraron más de una vez, el 8,3% lo hizo desde códigos postales distintos, lo que es consistente con que el sistema registre la dirección de cada compra.

### Hallazgos de la exploración

| Hallazgo | Implicancia para el análisis |
|---|---|
| **El 96,9% de los clientes compra una sola vez** (solo 2.997 vuelven) | La recompra es el gran problema del negocio. Una segmentación RFM de clientes aportaría poco, porque la frecuencia casi no varía |
| 775 pedidos no tienen productos, casi todos "no disponible" o cancelados | Son ventas que no se concretaron. Las ventas se calculan desde `order_items` |
| 547 pedidos tienen más de una reseña, y 789 reseñas cubren varios pedidos de una misma persona | Unir pedidos y reseñas sin cuidado duplica pedidos y sesga el análisis. Se usa una reseña por pedido |
| Hay pedidos con hasta 29 pagos | Cada voucher o gift card se registra como un pago aparte. El total del pedido es la suma de sus pagos |
| Los meses de 2016 y desde septiembre de 2018 tienen muy pocos pedidos | No es una caída real de ventas, sino el inicio de la plataforma y el corte de la extracción. Graficarlos mostraría un desplome falso |
| `geolocation` tiene unas 50 coordenadas por código postal, y 278 clientes no tienen coordenadas | Unir directo multiplicaría cada cliente. El análisis geográfico se hace por estado |
| Unos 190 pedidos tienen fechas imposibles (despachados antes de la compra o entregados antes del despacho) | Errores de registro. Se excluyen del análisis de atrasos |
| 610 productos sin categoría y 2 categorías sin traducción | Se agrupan como "sin_categoria" y se completan las traducciones |

### Reglas de limpieza

| # | Regla |
|---|---|
| 1 | Período de análisis: enero 2017 a agosto 2018 |
| 2 | Análisis de atrasos: solo pedidos entregados con fechas completas y coherentes |
| 3 | Una reseña por pedido (la más reciente, porque refleja la experiencia final) |
| 4 | El cliente es `customer_unique_id` |
| 5 | Productos sin categoría → "sin_categoria"; se agregan las 2 traducciones faltantes |
| 6 | Análisis geográfico por estado, no por coordenadas |
| 7 | Ventas desde `order_items` (precio + flete); los pagos solo se usan para analizar medios de pago |

### Preguntas de negocio y priorización

Las preguntas posibles se evaluaron según cuatro criterios: **impacto en el negocio**, **calidad de los datos** disponibles, **aporte de una mirada logística** y **técnicas** que permiten aplicar.

| Pregunta | Decisión | Por qué |
|---|---|---|
| ¿Los atrasos bajan la nota de las reseñas? | **Central** | Alto impacto y datos completos tras la limpieza. Incluye si la fecha prometida es exacta y si entregar antes mejora la nota |
| ¿El atraso se origina en el vendedor o en el transporte? | **Central** | El plazo de despacho del vendedor permite separar responsabilidades. Incluye en qué estados y rutas se concentran los atrasos |
| ¿Qué distingue a los clientes que vuelven a comprar? | **Central (reformulada)** | Era "¿qué clientes retener?", pero con 97% de compra única el problema real es por qué no vuelven |
| Segmentación de vendedores | **Central** | Ver la decisión de más abajo |
| ¿Cómo evolucionan las ventas y qué categorías y regiones concentran? | Contexto | Base necesaria para el dashboard |
| ¿El flete alto baja la nota? | Opcional | Interesante, pero secundaria |
| Medios de pago y cuotas | Descartada | Poca relación con las preguntas centrales |
| Análisis del texto de los comentarios | Descartada | En portugués, la mayoría vacíos y requiere otra técnica |
| Mapas con coordenadas exactas | Descartada | Coordenadas incompletas y muy duplicadas |

**¿A quién segmentar?** Se segmentan los **vendedores** y no los clientes. Olist es un marketplace con 3.095 vendedores que sí varían en volumen, atrasos, tiempo de despacho y nota promedio. Además, la segmentación conecta con la pregunta del origen del atraso y lleva a una acción concreta: a qué vendedores apoyar o exigir.

## Qué hace cada herramienta

- **SQL:** extraer, limpiar y responder todo lo que se resuelve contando, sumando y comparando grupos.
- **Python:** lo que SQL no hace bien: pruebas estadísticas, separar el efecto de cada factor y segmentación con k-means.
- **Power BI:** presentar los resultados de forma interactiva.

| Pregunta | SQL | Python | Power BI |
|---|---|---|---|
| Ventas (contexto) | Tendencia mensual (`LAG`), ranking de categorías (`RANK`), concentración de ventas (Pareto) | — | Página de resumen y ventas |
| ¿Los atrasos bajan la nota? | Nota promedio y % de malas reseñas por tramo de atraso | Prueba estadística y efecto del atraso separado de otros factores (flete, categoría, n° de ítems, región) | Página de logística y satisfacción |
| ¿Vendedor o transporte? | Tiempo de cada etapa del despacho, por estado y ruta | — | Página de logística y satisfacción |
| ¿Quiénes vuelven a comprar? | Primera compra de cada cliente (`ROW_NUMBER`) y comparación de su experiencia | Prueba de si las diferencias son significativas | Indicador de recompra |
| Segmentación de vendedores | Tabla de características por vendedor | k-means, nombre de cada segmento y resultado guardado en MySQL | Página de vendedores |

## Metodología

**Etapa 0: Carga y exploración** 

1. Creación de la base en MySQL con claves primarias y foráneas, y carga de los 9 CSV con `LOAD DATA`. Los códigos postales se guardaron como texto para conservar los ceros a la izquierda, y las celdas vacías como `NULL`.
2. Verificación de las filas cargadas contra los totales publicados en Kaggle.
3. Inventario de tablas y columnas con `information_schema`, y deducción de las relaciones entre tablas.
4. Verificación de hipótesis sobre claves, duplicados, valores faltantes y coherencia de fechas.
5. Definición de las reglas de limpieza y priorización de las preguntas de negocio.

**Etapa 1: SQL** *(pendiente)*

**Etapa 2: Python** *(pendiente)*

**Etapa 3: Power BI** *(pendiente)*

## Autor

Francisco Monsalve Bravo, Ingeniero Civil Industrial
