# MarchaRally · Objetivos terapéuticos (versión sincronizada)

Actividad interactiva de razonamiento clínico en kinesiología: 10 casos de marcha (parkinsoniana, atáxica sensitiva, cerebelosa, hemipléjica y atetósica) con alternativas y 2 casos de desarrollo para construir objetivos terapéuticos. 50 puntos y 60 minutos en total.

**App en vivo:** https://centrokinesicomouv-collab.github.io/marcharally/

## Cómo se usa en clase

1. **Docente** → pestaña *Docente* → *Crear sala* (nombre + PIN). Se genera un código de 6 caracteres.
2. *Proyectar QR*: los estudiantes escanean el QR (o entran a la app y escriben el código).
3. Cada estudiante se inscribe con nombre, RUT y equipo (crea uno o se une a uno; máximo 8 por equipo).
4. El docente presiona *Iniciar 60 minutos*: todos los teléfonos pasan a los desafíos al mismo tiempo.
5. El marcador por equipos y el panel docente se actualizan en vivo. Al final: *Exportar CSV*.

Para volver a una sala desde otro computador: *Docente* → *Abrir sala* con el código y el PIN.
Si un estudiante cierra el navegador o cambia de teléfono, vuelve a escribir su nombre y RUT y la app le ofrece **retomar su sesión**.

## Arquitectura

- `index.html`: toda la app (HTML + CSS + JavaScript). Usa [supabase-js](https://github.com/supabase/supabase-js) desde CDN.
- Base de datos: Supabase (PostgreSQL). La estructura está en `schema.sql`.
  - Tablas `rooms`, `teams`, `students` (lectura pública) y `room_secrets` (PIN docente, no legible desde el navegador).
  - Las inscripciones pasan por la función `register_student`, que bloquea la sala mientras procesa cada ingreso: valida RUT (dígito verificador), nombre, cupo de 8 por equipo, equipos y RUT duplicados, y que la inscripción siga abierta.
  - Iniciar y cerrar la evaluación exige el PIN docente (`set_room_phase`).
  - Actualización en vivo mediante Supabase Realtime, con consulta periódica de respaldo.

## Seguridad y privacidad

Es una herramienta de aula, no un sistema de evaluación con nota oficial:
- La clave pública de Supabase está en el código (es normal en apps web); las reglas de la base de datos limitan lo que se puede hacer con ella.
- Nombres, RUT y respuestas de una sala pueden ser leídos por alguien con conocimientos técnicos que tenga el código de la sala.
- Un estudiante con conocimientos técnicos podría modificar sus propias respuestas a través de la API.

## Plan gratuito de Supabase

El proyecto gratuito se **pausa tras 7 días sin uso**. Si la app muestra "Sin conexión con la base de datos", entra a supabase.com → proyecto *marcharally* → *Restore project* y espera un par de minutos.

## Licencias

El generador de códigos QR incluido es de Kazuhiko Arase (licencia MIT).
