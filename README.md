# Análisis de e-commerce y logística (Olist)

¿Los atrasos en la entrega bajan la satisfacción de los clientes? ¿El atraso se origina en el vendedor o en el transporte? ¿Por qué casi ningún cliente vuelve a comprar? Este proyecto analiza unos 100 mil pedidos reales de un marketplace brasileño en cuatro etapas: **exploración inicial** de una base desconocida, **SQL** para limpiar los datos y responder las preguntas de negocio, **Python** para separar el efecto de cada factor y segmentar a los vendedores, y **Power BI** para presentar los resultados.

>**Proyecto en desarrollo.** Etapas 0 (carga y exploración) y 1 (SQL) completas; Etapa 2 (Python) en curso. Las siguientes etapas se irán agregando a medida que avance el análisis.

## Hallazgos principales

*Pendiente: se completa al terminar el análisis.*

## Estructura del repositorio

```
analisis-ecommerce-logistica/
├── README.md
├── sql/
│   ├── 01_creacion_y_carga.sql       Creación de la base y carga de los 9 CSV
│   ├── 02_exploracion_inicial.sql    Inventario, verificación de hipótesis y reglas de limpieza
│   ├── 03_limpieza_vistas.sql        Reglas de limpieza convertidas en vistas
│   ├── 04_ventas.sql                 Tendencias, categorías y regiones
│   ├── 05_atrasos_y_resenas.sql      Atrasos, notas, promesa de entrega y origen del atraso
│   ├── 06_recompra.sql               Definición de recompra y clientes que vuelven
│   └── 07_vendedores.sql             Características de cada vendedor para la segmentación
├── python/
│   ├── 01_satisfaccion.ipynb         Efecto propio de cada factor en las malas reseñas
│   ├── 02_recompra.ipynb             (pendiente) Pruebas estadísticas de recompra
│   └── 03_segmentacion_vendedores.ipynb  (pendiente) Segmentación de vendedores con k-means
└── powerbi/                          (pendiente)
```

## Datos

- **Fuente:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), disponible en Kaggle. Son **datos reales y anonimizados** de Olist, un marketplace que conecta a pequeños vendedores con grandes tiendas online de Brasil.
- **Tamaño:** unos 100 mil pedidos entre 2016 y 2018, repartidos en 9 tablas relacionadas.
- Los CSV no se incluyen en el repositorio por su tamaño (unos 120 MB). Se descargan desde el link de Kaggle.

## Herramientas

- **MySQL 8** y MySQL Workbench
- **Python 3.11:** pandas, NumPy, SQLAlchemy, statsmodels, scikit-learn y matplotlib (Jupyter Notebook en VS Code)
- **Power BI Desktop:** DAX, Power Query

## Cómo reproducir el proyecto

1. Descargar los 9 CSV desde Kaggle.
2. En MySQL Workbench, habilitar la carga de archivos locales: *Edit Connection > Advanced > Others:* `OPT_LOCAL_INFILE=1`.
3. En `sql/01_creacion_y_carga.sql`, reemplazar `RUTA/A/TU/CARPETA/` por la carpeta donde quedaron los CSV y ejecutar el script. Al final muestra una verificación de filas cargadas.
4. Ejecutar los demás scripts en orden.
5. Instalar las librerías de Python (`pip install pandas sqlalchemy pymysql statsmodels scikit-learn matplotlib`) y ejecutar los notebooks de la carpeta `python/` en orden. Cada notebook pide la contraseña de MySQL al inicio, así no queda guardada en el código.

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
| 8 | Se excluyen los pedidos cancelados y no disponibles, porque no son ventas concretadas |

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

**Etapa 1: SQL**

1. **Reglas de limpieza convertidas en vistas**, para aplicarlas una sola vez y que todos los análisis partan de los mismos datos:
   - `v_resenas`: una reseña por pedido, la más reciente (`ROW_NUMBER`).
   - `v_productos`: categoría en inglés, sin vacíos.
   - `v_pedidos`: vista central, con una fila por pedido. Incluye el cliente real, los montos, la nota y los tiempos de cada etapa del despacho: preparación del vendedor, transporte, entrega total, plazo prometido, días de atraso y si el vendedor cumplió su plazo. Los tiempos solo se calculan para pedidos con fechas válidas, así ningún análisis de atrasos puede incluir fechas incompletas o imposibles.
   - `v_items`: una fila por producto vendido, con categoría y estados del vendedor y del cliente.
2. **Verificación de las vistas:** una sola reseña y una sola fila por pedido, y ventas que cuadran entre vistas (R$ 15,7 millones). Quedaron 97.905 pedidos en el período, y 96.018 sirven para analizar atrasos (98%).
3. **Ventas:** evolución mensual y crecimiento mes a mes (`LAG`), participación de cada categoría y concentración de ventas (sumas de ventana acumuladas), categoría líder por estado (`RANK` con `PARTITION BY`) y ventas por estado.
4. **Atrasos y reseñas:** nota y % de malas reseñas (1 o 2 estrellas) según atraso y tramo de atraso, holgura de la fecha prometida por estado, descomposición del tiempo de entrega en preparación del vendedor y transporte, efecto de recibir el pedido por partes, cambio de nota entre reseñas de un mismo pedido (`COUNT(*) OVER`, `MAX(CASE ...)`) y peso del flete por estado.
5. **Recompra:** tiempo entre la primera y la segunda compra (`LAG` con `PARTITION BY`), definición de recompra sin compras del mismo día y con igual tiempo de observación para todos, vista `v_clientes` con una fila por cliente y los datos de su primera compra, y comparación de la recompra según la nota y el atraso de la primera compra.
6. **Vendedores:** distribución de pedidos y ventas por vendedor, y vista `v_vendedores` con una fila por vendedor: volumen (pedidos, ventas, ticket, categorías, días activo) y calidad (preparación, cumplimiento de plazo, atrasos, nota y malas reseñas). Las métricas de calidad usan solo pedidos de un vendedor, para atribuir bien la responsabilidad. Es la base de la segmentación en Python.

**Etapa 2: Python** *(en curso)*

1. **Satisfacción:** regresión logística (statsmodels) para estimar el efecto propio de cada factor sobre la probabilidad de una mala reseña, comparando pedidos iguales en todo lo demás. Resultados expresados como razón de chances con intervalos de confianza, interacción entre atraso y flete, y traducción a probabilidades con escenarios de pedidos tipo.

**Etapa 3: Power BI** *(pendiente)*

## Análisis en SQL

### Ventas: ¿cómo evolucionan y dónde se concentran?

Las consultas completas están en [`sql/04_ventas.sql`](sql/04_ventas.sql). En el período analizado (enero 2017 a agosto 2018) se vendieron **R$ 15,7 millones en 97.905 pedidos**.

**1. Las ventas crecieron durante 2017 y se estancaron en 2018.**

| Período | Pedidos por mes | Ventas por mes | Ticket promedio |
|---|---:|---:|---:|
| Enero 2017 | 787 | R$ 137 mil | R$ 174 |
| Noviembre 2017 (peak) | 7.421 | R$ 1,17 millones | R$ 158 |
| Marzo a agosto 2018 | 6.100 a 7.200 | R$ 1,0 a 1,16 millones | R$ 155 a 168 |

- El mes con más ventas es **noviembre 2017 (+53%)**, por el Black Friday. Diciembre cae un 26,5%.
- Desde marzo de 2018 las ventas se mantienen entre R$ 1,0 y 1,16 millones mensuales, sin crecer.
- El ticket promedio casi no cambia (R$ 147 a 175): el crecimiento vino de **más pedidos, no de pedidos más caros**.
- Esto es consistente con el problema de recompra: si el 96,9% de los clientes compra una sola vez, crecer depende de captar clientes nuevos todo el tiempo.

**2. Las ventas están repartidas entre muchas categorías.**

| Categoría | % de las ventas | % acumulado |
|---|---:|---:|
| Salud y belleza | 9,1% | 9,1% |
| Relojes y regalos | 8,3% | 17,4% |
| Cama, mesa y baño | 7,9% | 25,3% |
| Deportes y ocio | 7,3% | 32,6% |
| Accesorios de computación | 6,7% | 39,3% |

- Ninguna categoría domina: la primera tiene solo el 9,1%. Hacen falta **18 categorías para llegar al 80%** de las ventas.
- Salud y belleza es la categoría líder en 15 de los 27 estados, sobre todo en el norte y nordeste. Los estados grandes tienen preferencias distintas: cama, mesa y baño en SP; relojes y regalos en RJ.

**3. Las ventas sí están concentradas geográficamente.**

| Estado | % de las ventas | % acumulado |
|---|---:|---:|
| São Paulo (SP) | 37,4% | 37,4% |
| Río de Janeiro (RJ) | 13,4% | 50,8% |
| Minas Gerais (MG) | 11,7% | 62,5% |

- Solo SP es más de un tercio de las ventas, y con **7 de los 27 estados se llega al 80%**.
- El valor por pedido es mayor en los estados alejados del sudeste (por ejemplo, R$ 265 en Paraíba contra R$ 143 en SP). Una posible explicación es el costo del flete, que se revisa en el análisis de atrasos.

### Atrasos y satisfacción: ¿qué hace que un cliente quede insatisfecho?

Las consultas completas están en [`sql/05_atrasos_y_resenas.sql`](sql/05_atrasos_y_resenas.sql). Se analizaron los 96.018 pedidos entregados con fechas válidas. Se considera mala reseña una nota de 1 o 2 estrellas.

**1. Un atraso baja la nota en 2 estrellas, y cada día extra pesa más.**

| Entrega | Pedidos | Nota promedio | % malas reseñas |
|---|---:|---:|---:|
| Más de 7 días antes de lo prometido | 70.520 | 4,32 | 8,9% |
| 0 a 7 días antes | 18.481 | 4,19 | 10,4% |
| 1 a 3 días tarde | 1.850 | 3,29 | 32,2% |
| 4 a 7 días tarde | 1.746 | 2,10 | 67,6% |
| Más de 7 días tarde | 2.779 | 1,70 | 79,3% |

- Solo el 6,8% de los pedidos llega tarde, pero con más de una semana de atraso **4 de cada 5 clientes ponen 1 o 2 estrellas**.
- Llegar antes de lo prometido casi no mejora la nota. La satisfacción depende de **cumplir la promesa, no de llegar rápido**.

**2. Las fechas prometidas son muy holgadas, y el atraso depende de cómo se calibra la promesa, no de la distancia.**

- El 79% de los pedidos a tiempo llega con más de una semana de anticipación. En São Paulo se prometen 19 días y el pedido llega en 8,7.
- El **Nordeste** concentra los atrasos (hasta 21,5% en Alagoas), con promesas de ~30 días y solo 8 a 10 días de margen. El **Norte**, la región más lejana, casi no se atrasa (menos de 4%) porque se le prometen 41 a 46 días.
- **Río de Janeiro** es una excepción: está junto a São Paulo, pero se atrasa casi 3 veces más (12,2% vs 4,5%), y es el segundo mercado más grande.

**3. El vendedor multiplica el riesgo, pero la mayoría de los atrasos ocurre en el transporte.**

| | Pedidos | Preparación (vendedor) | Transporte | % atrasados |
|---|---:|---:|---:|---:|
| Vendedor cumplió su plazo | 87.448 | 2,6 días | 9,3 días | 5,4% |
| Vendedor fuera de plazo | 8.570 | 9,5 días | 9,9 días | 21,1% |

- Cuando el vendedor no cumple, el pedido tiene **4 veces más probabilidad** de llegar tarde, y el transporte no recupera el tiempo perdido.
- Pero los vendedores cumplen el 91% de las veces, así que **el 72% de los pedidos atrasados tuvo un vendedor que cumplió**. En volumen, el problema principal es el transporte.

**4. Recibir el pedido por partes baja la nota, aunque llegue a tiempo.**

| Pedidos a tiempo | Pedidos | Nota promedio | % malas reseñas |
|---|---:|---:|---:|
| Un vendedor, un ítem | 80.022 | 4,36 | 7,5% |
| Un vendedor, varios ítems | 7.756 | 3,85 | 21,0% |
| Varios vendedores | 1.223 | 2,88 | 46,8% |

- Un pedido con varios vendedores, que suele llegar en paquetes separados, tiene peor nota que uno con 1 a 3 días de atraso.
- En los pocos pedidos con varias reseñas, **cuando la nota sube, el pedido solía tener varios vendedores o ítems**: consistente con un cliente que evalúa mal al recibir una parte y mejora la nota cuando llega lo que faltaba. Son grupos pequeños (unos 10 pedidos), por lo que es una señal y no una conclusión.

**5. El flete pesa casi el doble en los estados lejanos, pero no parece bajar la nota.**

- El flete es el 12,2% de lo que paga un cliente en São Paulo y entre 17% y 22% en el Norte y el Nordeste. Los clientes lejanos también compran productos más caros.
- La nota sigue a los atrasos, no al flete: el Norte paga fletes altos pero tiene buenas notas y pocos atrasos, mientras que Río de Janeiro paga fletes bajos pero tiene mala nota y muchos atrasos.

### Recompra: ¿por qué los clientes no vuelven?

Las consultas completas están en [`sql/06_recompra.sql`](sql/06_recompra.sql).

**Definir bien qué es "volver".** Antes de comparar, se corrigieron dos trampas:

- **El 30% de las "segundas compras" ocurrió el mismo día** que la primera. No es recompra: el cliente aún no había recibido nada.
- **No todos tuvieron el mismo tiempo para volver.** Un cliente que compró por primera vez en agosto de 2018 casi no tiene datos posteriores.

Por eso se definió que un cliente **volvió** si hizo otra compra en un día distinto dentro de los 180 días siguientes (el plazo en que vuelve el 76% de los recurrentes), y solo se consideraron los **56.338 clientes con primera compra antes de marzo de 2018**, que tuvieron al menos 6 meses para volver.

**1. Solo el 2% de los clientes vuelve a comprar en 6 meses** (1.121 de 56.338).

**2. La experiencia de la primera compra influye poco en volver.**

| Primera compra | % recompra |
|---|---:|
| Nota 5 | 2,15% |
| Nota 1 | 1,68% |
| Llegó a tiempo | 2,02% |
| Llegó atrasada | 1,61% |

- Una mala nota o un atraso bajan la recompra solo unas décimas. **Incluso los clientes que pusieron 5 estrellas casi no vuelven.**
- La baja recompra parece un **problema estructural, no logístico**. Una hipótesis: Olist conecta a vendedores pequeños con grandes tiendas online, y el cliente compra en la tienda grande muchas veces sin saber que detrás está Olist. Si vuelve a esa tienda y le compra a otro vendedor, esa compra no aparece en estos datos.
- Es una conclusión negativa, pero valiosa: mejorar la logística mejora la satisfacción, pero no basta para que los clientes vuelvan.

### Vendedores: ¿qué tan distintos son?

Las consultas completas están en [`sql/07_vendedores.sql`](sql/07_vendedores.sql).

**1. Pocos vendedores concentran la mayor parte de las ventas.**

| Pedidos por vendedor | % de vendedores | % de las ventas |
|---|---:|---:|
| Menos de 10 | 58,5% | 8,9% |
| 10 a 199 | 38,5% | 53,4% |
| 200 o más | 3,0% | 37,7% |

- **91 vendedores (3%) generan el 38% de las ventas**, mientras que casi 6 de cada 10 tienen menos de 10 pedidos.
- Para la segmentación se usan los **1.258 vendedores con 10 o más pedidos**, que generan el 91% de las ventas. Con menos pedidos, las tasas no son confiables (un solo atraso en 1 pedido es un 100%).

**2. Los vendedores que no cumplen su plazo tienen más atrasos y peores notas.**

| Cumplimiento del plazo de despacho | Vendedores | Preparación | % atrasados | Nota |
|---|---:|---:|---:|---:|
| Siempre cumple | 372 | 1,9 días | 4,9% | 4,29 |
| Hasta 10% fuera de plazo | 497 | 2,6 días | 6,0% | 4,22 |
| 10 a 25% fuera de plazo | 242 | 4,2 días | 7,8% | 4,09 |
| Más de 25% fuera de plazo | 147 | 6,9 días | 12,7% | 3,77 |

- Los vendedores que más fallan tienen **2,6 veces más atrasos** que los que siempre cumplen.
- Incluso los vendedores que siempre cumplen tienen un 4,9% de atrasos: ese es el atraso propio del transporte.
- Las diferencias entre vendedores son claras, lo que justifica segmentarlos.

## Análisis en Python

### Satisfacción: ¿qué factores causan una mala reseña?

El notebook completo está en [`python/01_satisfaccion.ipynb`](python/01_satisfaccion.ipynb).

En SQL, algunos factores aparecían mezclados: el Nordeste tiene fletes altos y también muchos atrasos, y los pedidos con varios vendedores tienen más ítems y más valor. Una **regresión logística** con 95.376 pedidos permite separar el efecto propio de cada factor, **comparando pedidos iguales en todo lo demás** (atraso, tipo de pedido, región, flete y valor).

**Probabilidad estimada de mala reseña (1 o 2 estrellas) según el modelo:**

| Pedido (Sudeste, flete y valor típicos) | Probabilidad de mala reseña |
|---|---:|
| Típico: un vendedor, un ítem, llega con holgura | 7,3% |
| A tiempo, varios ítems de un vendedor | 17,7% |
| Llega 1 a 3 días tarde | 29,8% |
| **A tiempo, pero con varios vendedores** | **43,1%** |
| Llega 4 a 7 días tarde | 65,7% |
| Llega más de 7 días tarde | 77,9% |

- **El atraso es el factor más fuerte.** Con más de 7 días de atraso, las chances de una mala reseña se multiplican por 45 (de 7% a 78% de probabilidad).
- **Recibir el pedido por partes tiene efecto propio.** Un pedido a tiempo pero con varios vendedores, que suele llegar en paquetes separados, tiene más riesgo que uno que llega 1 a 3 días tarde. El efecto se mantiene al comparar pedidos con el mismo flete y valor.
- **La región no tiene efecto propio.** Las peores notas del Nordeste se explican por sus atrasos, no por la región.
- **El flete pesa poco, y solo cuando el pedido llega a tiempo.** En pedidos a tiempo, duplicar el flete sube un 13% las chances de mala reseña; en pedidos atrasados no tiene efecto, porque el atraso domina la experiencia.
- **El valor del producto no influye en la nota.**

## Autor

Francisco Monsalve Bravo, Ingeniero Civil Industrial
