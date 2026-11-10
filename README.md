# MarchaRally · Objetivos terapéuticos

Actividad interactiva de razonamiento clínico en kinesiología: 10 casos de marcha (parkinsoniana, atáxica sensitiva, cerebelosa, hemipléjica y atetósica) con alternativas y 2 casos de desarrollo para construir objetivos terapéuticos. 50 puntos y 60 minutos en total.

**App en vivo:** https://centrokinesicomouv-collab.github.io/marcharally/

Toda la aplicación está en un único archivo: `index.html` (HTML + CSS + JavaScript, sin dependencias externas).

## Vistas

- **Estudiantes**: registro con nombre, RUT y equipo, y luego los 12 desafíos.
- **Equipos + QR**: pantalla para proyectar con el código QR, el reloj y el marcador por equipos.
- **Docente**: acceso con PIN, creación de la sala, inicio y cierre de los 60 minutos, revisión de rúbricas y exportación a CSV.

Enlaces directos: `#docente` y `#qr`.

## Limitación importante

Esta versión guarda los datos **solo en el navegador de cada dispositivo** (localStorage). Si cada estudiante la abre en su propio teléfono, los equipos y puntajes **no se comparten** entre dispositivos ni con el panel docente. Para una clase sincronizada se necesita una versión con servidor o base de datos compartida.

## Licencias

El generador de códigos QR incluido es de Kazuhiko Arase (licencia MIT).
