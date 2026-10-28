-- =====================================================================
-- Proyecto: Análisis de e-commerce y logística (dataset Olist)
-- Script 04: Ventas (contexto del negocio)
-- Motor: MySQL 8
-- =====================================================================
-- Objetivo: entender cómo evolucionan las ventas y dónde se concentran,
-- como base para las preguntas centrales y para el dashboard.
--
-- Todas las consultas parten de las vistas limpias del script 03.
-- Ventas = precio + flete (regla 7). Montos en reales brasileños (R$).
--
-- Técnicas: GROUP BY, CTE (WITH) y funciones de ventana
-- (LAG, SUM ... OVER, RANK, PARTITION BY).
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. Ventas mensuales
-- ---------------------------------------------------------------------
-- v_pedidos tiene una fila por pedido, por eso COUNT(*) = n° de pedidos.

SELECT mes_compra                            AS mes,
       COUNT(*)                              AS n_pedidos,
       ROUND(SUM(valor_total), 2)            AS ventas_totales,
       ROUND(SUM(valor_total) / COUNT(*), 2) AS ticket_promedio
FROM v_pedidos
GROUP BY mes_compra
ORDER BY mes_compra;

/* Resultado:

   mes       pedidos      ventas   ticket promedio
   2017-01       787     136.943        174,01
   2017-02     1.718     283.562        165,05
   2017-03     2.617     425.618        162,64
   2017-04     2.377     405.849        170,74
   2017-05     3.640     582.711        160,09
   2017-06     3.205     499.652        155,90
   2017-07     3.946     578.754        146,67
   2017-08     4.272     661.904        154,94
   2017-09     4.227     717.103        169,65
   2017-10     4.547     764.756        168,19
   2017-11     7.421   1.172.192        157,96
   2017-12     5.618     861.527        153,35
   2018-01     7.187   1.101.920        153,32
   2018-02     6.624     979.486        147,87
   2018-03     7.168   1.152.657        160,81
   2018-04     6.919   1.156.249        167,11
   2018-05     6.833   1.145.686        167,67
   2018-06     6.145   1.020.382        166,05
   2018-07     6.233   1.039.784        166,82
   2018-08     6.421     996.974        155,27

   - Los pedidos crecen fuerte durante 2017 y en 2018 se estabilizan en torno
     a 6.000-7.000 al mes.
   - Noviembre 2017 es el mes peak (7.421 pedidos), por el Black Friday.
   - El ticket promedio casi no cambia (R$ 147-175): el crecimiento viene de
     más pedidos, no de pedidos más caros. */

-- ---------------------------------------------------------------------
-- 2. Crecimiento mes a mes
-- ---------------------------------------------------------------------
-- El CTE resume las ventas por mes (20 filas). Sobre ese resultado, LAG
-- trae las ventas de la fila anterior, o sea, del mes anterior.
-- El primer mes queda en NULL porque no tiene un mes anterior.

WITH ventas_mes AS (
    SELECT mes_compra                            AS mes,
           COUNT(*)                              AS n_pedidos,
           SUM(valor_total)                      AS ventas_totales,
           ROUND(SUM(valor_total) / COUNT(*), 2) AS ticket_promedio
    FROM v_pedidos
    GROUP BY mes_compra
)
SELECT mes,
       n_pedidos,
       ventas_totales,
       LAG(ventas_totales) OVER (ORDER BY mes) AS ventas_mes_anterior,
       ROUND((ventas_totales - LAG(ventas_totales) OVER (ORDER BY mes))
             / LAG(ventas_totales) OVER (ORDER BY mes) * 100, 1) AS crecimiento_pct
FROM ventas_mes
ORDER BY mes;

/* Resultado (crecimiento % respecto al mes anterior):
   2017: feb +107,1 | mar +50,1 | abr -4,6 | may +43,6 | jun -14,3 | jul +15,8 |
         ago +14,4 | sep +8,3 | oct +6,6 | nov +53,3 | dic -26,5
   2018: ene +27,9 | feb -11,1 | mar +17,7 | abr +0,3 | may -0,9 | jun -10,9 |
         jul +1,9 | ago -4,1

   - Los porcentajes altos de inicios de 2017 se deben a que se parte de una
     base pequeña (la plataforma recién comenzaba). Comparar porcentajes sobre
     bases muy distintas puede exagerar el crecimiento.
   - El Black Friday se ve claramente: +53% en noviembre y -26,5% en diciembre.
   - En 2018 el crecimiento se frena: desde marzo las ventas se mantienen en
     torno a R$ 1,0-1,15 millones mensuales. Esto es consistente con el
     hallazgo de la recompra (96,9% compra una sola vez): si los clientes no
     vuelven, crecer depende de captar clientes nuevos todo el tiempo. */

-- ---------------------------------------------------------------------
-- 3. Top 10 categorías por ventas
-- ---------------------------------------------------------------------
-- SUM(SUM(...)) OVER (): el SUM interior son las ventas de cada categoría
-- (se calcula en el GROUP BY); el SUM ... OVER () exterior suma todas las
-- categorías del resultado = total general.
-- El LIMIT se ejecuta al final, así que el % se calcula sobre TODAS las
-- categorías y recién después se muestran solo 10.

SELECT categoria,
       ROUND(SUM(precio + flete), 2) AS ventas,
       ROUND(SUM(precio + flete) * 100
             / SUM(SUM(precio + flete)) OVER (), 1) AS pct_del_total
FROM v_items
GROUP BY categoria
ORDER BY ventas DESC
LIMIT 10;

/* Resultado:
   health_beauty          1.432.213   9,1%
   watches_gifts          1.294.824   8,3%
   bed_bath_table         1.239.780   7,9%
   sports_leisure         1.144.754   7,3%
   computers_accessories  1.049.201   6,7%
   furniture_decor          892.438   5,7%
   housewares               770.493   4,9%
   cool_stuff               702.849   4,5%
   auto                     676.854   4,3%
   garden_tools             578.060   3,7%

   - Ninguna categoría domina: la primera tiene solo el 9,1% y las 10 primeras
     suman cerca del 62%. Es típico de un marketplace con miles de vendedores.
   - Relojes y regalos es la segunda en ventas; hipótesis: por ser productos
     de precio alto más que por cantidad vendida. */

-- ---------------------------------------------------------------------
-- 4. Pareto de categorías (% acumulado)
-- ---------------------------------------------------------------------
-- Con ORDER BY dentro del OVER, la suma deja de ser el total y se va
-- acumulando fila por fila, de la categoría más vendida a la menos vendida.
-- % acumulado = suma acumulada hasta esta categoría / total de todas.
-- Dentro del OVER no se puede usar el alias "ventas" (los alias del SELECT
-- aún no existen cuando se calcula la ventana), por eso se repite la expresión.

SELECT categoria,
       ROUND(SUM(precio + flete), 2) AS ventas,
       ROUND(SUM(precio + flete) * 100
             / SUM(SUM(precio + flete)) OVER (), 2) AS pct_del_total,
       ROUND(SUM(SUM(precio + flete)) OVER (ORDER BY SUM(precio + flete) DESC) * 100
             / SUM(SUM(precio + flete)) OVER (), 2) AS pct_acumulado
FROM v_items
GROUP BY categoria
ORDER BY ventas DESC;

/* Resultado (hasta superar el 80%):

    #   categoría               % del total   % acumulado
    1   health_beauty               9,13          9,13
    2   watches_gifts               8,26         17,39
    3   bed_bath_table              7,90         25,29
    4   sports_leisure              7,30         32,59
    5   computers_accessories       6,69         39,28
    6   furniture_decor             5,69         44,97
    7   housewares                  4,91         49,88
    8   cool_stuff                  4,48         54,37
    9   auto                        4,32         58,68
   10   garden_tools                3,69         62,37
   11   toys                        3,52         65,89
   12   baby                        3,04         68,93
   13   perfumery                   2,84         71,77
   14   telephony                   2,51         74,27
   15   office_furniture            2,17         76,44
   16   stationery                  1,76         78,20
   17   pet_shop                    1,61         79,81
   18   computers                   1,48         81,30

   - 18 categorías concentran el 80% de las ventas, cerca de un cuarto del
     total de categorías: parecido a la regla de Pareto (20/80).
   - A diferencia de un Pareto clásico, arriba no hay categorías dominantes:
     la curva sube de forma pareja. Las ventas dependen de un grupo amplio de
     categorías y no de una o dos. */

-- ---------------------------------------------------------------------
-- 5. Categoría líder en cada estado
-- ---------------------------------------------------------------------
-- Paso 1 (CTE): ventas de cada categoría en cada estado.
--   Toda columna del SELECT que no esté dentro de una agregación debe ir
--   en el GROUP BY: por eso se agrupa por estado Y categoría.
-- Paso 2 (CTE): PARTITION BY divide la ventana por estado, así el ranking
--   (RANK) y el % se calculan dentro de cada estado por separado.
-- Paso 3: filtrar la posición 1. Se necesita un CTE aparte porque el WHERE
--   se ejecuta antes que el SELECT: no puede filtrar por una columna que se
--   calcula en el mismo SELECT.

WITH ventas_estado_categoria AS (
    SELECT estado_cliente,
           categoria,
           ROUND(SUM(precio + flete), 2) AS ventas
    FROM v_items
    GROUP BY estado_cliente, categoria
),
ranking AS (
    SELECT estado_cliente,
           categoria,
           ventas,
           ROUND(ventas * 100 / SUM(ventas) OVER (PARTITION BY estado_cliente), 1) AS pct_del_estado,
           RANK() OVER (PARTITION BY estado_cliente ORDER BY ventas DESC)         AS posicion
    FROM ventas_estado_categoria
)
SELECT estado_cliente, categoria, ventas, pct_del_estado
FROM ranking
WHERE posicion = 1
ORDER BY ventas DESC;

/* Resultado (27 estados, ordenados por ventas de su categoría líder):

   estado  categoría líder         ventas   % del estado
   SP      bed_bath_table         555.619    9,5
   RJ      watches_gifts          196.333    9,3
   MG      health_beauty          177.645    9,7
   RS      bed_bath_table          72.714    8,3
   PR      sports_leisure          67.614    8,5
   BA      health_beauty           60.087    9,9
   SC      sports_leisure          50.818    8,4
   PE      health_beauty           49.823   15,6
   CE      health_beauty           37.898   13,9
   GO      watches_gifts           35.111   10,3
   DF      watches_gifts           34.918   10,0
   ES      watches_gifts           32.094   10,0
   PA      health_beauty           27.826   12,9
   PB      health_beauty           19.454   13,9
   MT      health_beauty           17.822    9,6
   RN      health_beauty           16.219   16,1
   MA      health_beauty           15.579   10,4
   AL      health_beauty           14.870   15,5
   MS      health_beauty           12.739    9,4
   PI      health_beauty           12.023   11,2
   SE      health_beauty           10.183   14,0
   RO      health_beauty            7.968   13,9
   TO      sports_leisure           6.454   10,6
   AM      health_beauty            3.369   12,1
   AP      computers_accessories    2.443   15,0
   AC      sports_leisure           2.072   10,5
   RR      sports_leisure           1.743   17,9

   - Salud y belleza lidera en 15 de los 27 estados, sobre todo en el norte y
     nordeste. Por eso es la categoría número 1 del país.
   - Los estados grandes tienen preferencias distintas: cama, mesa y baño en
     SP y RS; relojes y regalos en RJ, GO, DF y ES; deportes en PR y SC.
   - En los estados pequeños la categoría líder concentra más (13-18%) que en
     los grandes (~9%), aunque con ventas tan bajas unos pocos pedidos mueven
     mucho el porcentaje. */

-- ---------------------------------------------------------------------
-- 6. Ventas por estado del cliente
-- ---------------------------------------------------------------------
-- Base para el mapa del dashboard. Usa v_pedidos (una fila por pedido),
-- por eso COUNT(*) = n° de pedidos.

SELECT estado_cliente,
       COUNT(*)                   AS pedidos,
       ROUND(SUM(valor_total), 2) AS ventas,
       ROUND(SUM(valor_total) * 100
             / SUM(SUM(valor_total)) OVER (), 1) AS pct_del_total,
       ROUND(SUM(SUM(valor_total)) OVER (ORDER BY SUM(valor_total) DESC) * 100
             / SUM(SUM(valor_total)) OVER (), 1) AS pct_acumulado
FROM v_pedidos
GROUP BY estado_cliente
ORDER BY ventas DESC;

/* Resultado:

   estado   pedidos      ventas   % del total   % acumulado
   SP        41.021   5.863.233      37,4          37,4
   RJ        12.654   2.105.550      13,4          50,8
   MG        11.457   1.837.646      11,7          62,5
   RS         5.395     873.635       5,6          68,1
   PR         4.962     791.702       5,0          73,1
   BA         3.340     605.913       3,9          77,0
   SC         3.590     605.523       3,9          80,9
   DF         2.114     350.127       2,2          83,1
   GO         1.990     339.390       2,2          85,3
   ES         2.014     322.014       2,1          87,3
   PE         1.636     319.330       2,0          89,4
   CE         1.316     272.573       1,7          91,1
   PA           965     216.197       1,4          92,5
   MT           900     185.502       1,2          93,7
   MA           732     149.689       1,0          94,6
   PB           530     140.449       0,9          95,5
   MS           708     135.876       0,9          96,4
   PI           489     107.519       0,7          97,1
   RN           478     101.014       0,6          97,7
   AL           409      96.100       0,6          98,3
   SE           342      72.686       0,5          98,8
   TO           278      61.104       0,4          99,2
   RO           246      57.424       0,4          99,5
   AM           147      27.836       0,2          99,7
   AC            81      19.670       0,1          99,8
   AP            68      16.263       0,1          99,9
   RR            43       9.744       0,1         100,0

   - Las ventas están muy concentradas geográficamente: SP solo es el 37,4%,
     y SP, RJ y MG (sudeste) suman el 62,5%. Con 7 estados (sudeste, sur y BA)
     se llega al 80%.
   - A diferencia de las categorías, aquí sí hay un Pareto marcado: 7 de 27
     estados concentran el 80% de las ventas.
   - El valor promedio por pedido es mayor en los estados lejanos del sudeste
     (por ejemplo, PB ~R$ 265 y AL ~R$ 235, contra ~R$ 143 en SP).
     Hipótesis: el flete es más caro en los estados lejanos, porque la mayoría
     de los vendedores está en el sudeste. Se revisa en el script 05. */
