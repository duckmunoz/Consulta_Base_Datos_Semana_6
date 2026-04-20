-- Caso 1--

-- Etapa 1:
DROP TABLE recaudacion_bonos_medicos;

CREATE TABLE recaudacion_bonos_medicos (
    rut_medico      VARCHAR2(12),
    nombre_medico   VARCHAR2(60),
    total_recaudado NUMBER(10),
    unidad_medica   VARCHAR2(40)
);
 
-- Etapa 2:
INSERT INTO recaudacion_bonos_medicos (
    rut_medico,
    nombre_medico,
    total_recaudado,
    unidad_medica
)
    SELECT
        to_char(m.rut_med)
        || '-'
        || m.dv_run         AS rut_medico,
        m.pnombre
        || ' '
        || m.apaterno
        || ' '
        || m.amaterno       AS nombre_medico,
        round(sum(b.costo)) AS total_recaudado,
        u.nombre            AS unidad_medica
    FROM
             medico m
        JOIN det_especialidad_med dem ON m.rut_med = dem.rut_med
        JOIN bono_consulta        b ON b.rut_med = dem.rut_med
                                AND b.esp_id = dem.esp_id
        JOIN unidad_consulta      u ON u.uni_id = m.uni_id
    WHERE
    -- Solo bonos del año anterior al actual
            EXTRACT(YEAR FROM b.fecha_bono) = EXTRACT(YEAR FROM sysdate) - 1
    -- Excluir cargos directivos
        AND m.car_id NOT IN ( 100, 500, 600 )
    GROUP BY
        m.rut_med,
        m.dv_run,
        m.pnombre,
        m.apaterno,
        m.amaterno,
        u.nombre
    ORDER BY
        total_recaudado ASC;

COMMIT;
 
-- Verificación del resultado
SELECT
    rut_medico,
    nombre_medico,
    '$' || to_char(total_recaudado, 'FM999,999,999') AS total_recaudado,
    unidad_medica
FROM
    recaudacion_bonos_medicos
ORDER BY
    TO_NUMBER(regexp_replace(total_recaudado, '[^0-9]', '')) ASC;

--Caso 2--

SELECT
    especialidad_medica,
    cantidad_bonos,
    '$' || to_char(monto_perdida, 'FM999,999') AS "MONTO PÉRDIDA",
    to_char(fecha_bono, 'DD-MM-YYYY')          AS fecha_bono,
    estado_de_cobro
FROM
    (
        SELECT
            upper(e.nombre)     AS especialidad_medica,
            COUNT(b.id_bono)    AS cantidad_bonos,
            round(sum(b.costo)) AS monto_perdida,
            MIN(b.fecha_bono)   AS fecha_bono,
            CASE
                WHEN EXTRACT(YEAR FROM MIN(b.fecha_bono)) >= EXTRACT(YEAR FROM sysdate) - 1 THEN
                    'COBRABLE'
                ELSE
                    'INCOBRABLE'
            END                 AS estado_de_cobro
        FROM
                 bono_consulta b
            JOIN especialidad_medica e ON e.esp_id = b.esp_id
        WHERE
            b.id_bono IN (
                SELECT
                    id_bono
                FROM
                    bono_consulta
                MINUS
                SELECT
                    id_bono
                FROM
                    pagos
            )
        GROUP BY
            e.nombre
    )
ORDER BY
    cantidad_bonos ASC,
    monto_perdida DESC;

--Caso 3--

SELECT
    EXTRACT(YEAR FROM sysdate)                              AS annio_calculo,
    p.pac_run                                               AS pac_run,
    p.dv_run                                                AS dv_run,
    round(months_between(sysdate, p.fecha_nacimiento) / 12) AS edad,
    COUNT(b.id_bono)                                        AS cantidad_bonos,
    round(nvl(
        sum(b.costo),
        0
    ))                                                      AS monto_total_bonos,
    ss.descripcion                                          AS sistema_salud
FROM
         paciente p
    JOIN salud         s ON s.sal_id = p.sal_id
    JOIN sistema_salud ss ON ss.tipo_sal_id = s.tipo_sal_id
    LEFT JOIN bono_consulta b ON b.pac_run = p.pac_run
                                 AND EXTRACT(YEAR FROM b.fecha_bono) = EXTRACT(YEAR FROM sysdate) - 1
WHERE
    ss.tipo_sal_id IN ( 'F', 'P', 'FA' )
GROUP BY
    p.pac_run,
    p.dv_run,
    p.fecha_nacimiento,
    ss.descripcion
HAVING
    COUNT(b.id_bono) <= (
        -- Subconsulta: promedio redondeado de bonos del año anterior
        SELECT
            round(COUNT(*) / COUNT(DISTINCT pac_run))
        FROM
            bono_consulta
        WHERE
            EXTRACT(YEAR FROM fecha_bono) = EXTRACT(YEAR FROM sysdate) - 1
    )
ORDER BY
    monto_total_bonos ASC,
    edad DESC;

-- Etapa 2:
INSERT INTO cant_bonos_pacientes_annio (
    annio_calculo,
    pac_run,
    dv_run,
    edad,
    cantidad_bonos,
    monto_total_bonos,
    sistema_salud
)
    SELECT
        EXTRACT(YEAR FROM sysdate)                              AS annio_calculo,
        p.pac_run                                               AS pac_run,
        p.dv_run                                                AS dv_run,
        round(months_between(sysdate, p.fecha_nacimiento) / 12) AS edad,
        COUNT(b.id_bono)                                        AS cantidad_bonos,
        round(nvl(
            sum(b.costo),
            0
        ))                                                      AS monto_total_bonos,
        upper(ss.descripcion)                                   AS sistema_salud
    FROM
             paciente p
        JOIN salud         s ON s.sal_id = p.sal_id
        JOIN sistema_salud ss ON ss.tipo_sal_id = s.tipo_sal_id
        LEFT JOIN bono_consulta b ON b.pac_run = p.pac_run
                                     AND EXTRACT(YEAR FROM b.fecha_bono) = EXTRACT(YEAR FROM sysdate) - 1
    WHERE
        ss.tipo_sal_id IN ( 'F', 'P', 'FA' )
    GROUP BY
        p.pac_run,
        p.dv_run,
        p.fecha_nacimiento,
        ss.descripcion
    HAVING
        COUNT(b.id_bono) <= (
            SELECT
                round(COUNT(*) / COUNT(DISTINCT pac_run))
            FROM
                bono_consulta
            WHERE
                EXTRACT(YEAR FROM fecha_bono) = EXTRACT(YEAR FROM sysdate) - 1
        )
    ORDER BY
        monto_total_bonos ASC,
        edad DESC;

COMMIT;

-- Verificación del resultado final
SELECT
    annio_calculo,
    pac_run,
    dv_run,
    edad,
    cantidad_bonos,
    monto_total_bonos,
    sistema_salud
FROM
    cant_bonos_pacientes_annio
WHERE
    annio_calculo = EXTRACT(YEAR FROM sysdate)
ORDER BY
    monto_total_bonos ASC,
    edad DESC;

