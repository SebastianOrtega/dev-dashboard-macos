# Dev Dashboard

Herramienta local para macOS orientada a desarrolladores que muestra procesos de desarrollo escuchando puertos y permite cerrarlos desde una UI simple.

## Qué hace

- Detecta procesos de desarrollo que estén escuchando puertos TCP.
- Muestra PID, nombre, comando completo, puertos, dirección, runtime, carpeta de trabajo y tipo estimado.
- Resalta procesos duplicados o sospechosos.
- Permite refrescar manualmente, usar auto refresh, buscar y cerrar procesos.
- Permite cerrar todos los procesos asociados a una misma carpeta cuando se puede inferir.

## Stack

- Frontend: React + Vite
- Backend: Node.js + Express
- Detección del sistema: `lsof` + `ps`

## Arquitectura mínima

```text
dev_dashboard/
├── client/               # UI React/Vite
│   ├── src/App.jsx
│   ├── src/main.jsx
│   └── src/styles.css
├── server/               # API local + detector macOS
│   └── src/
│       ├── config.js
│       ├── index.js
│       └── processScanner.js
├── package.json          # scripts raíz
└── README.md
```

## Requisitos

- macOS
- Node.js 20+ recomendado
- npm 10+ recomendado

## Instalación

```bash
npm install
```

## Cómo correrlo

### Desarrollo completo

Arranca backend y frontend con un solo comando:

```bash
npm run dev
```

### Solo backend

```bash
npm run server
```

### Solo frontend

```bash
npm run client
```

## URLs locales

- UI: [http://127.0.0.1:7001](http://127.0.0.1:7001)
- API: [http://127.0.0.1:7000/api/processes](http://127.0.0.1:7000/api/processes)

La herramienta escucha solo en `127.0.0.1`.

## Scripts npm

- `npm run dev`: levanta backend + frontend.
- `npm run server`: arranca el backend local.
- `npm run client`: arranca la UI local.
- `npm run build`: genera build del frontend.
- `npm run start`: arranca el backend sin watch.

## Qué comandos del sistema usa

La detección se apoya en comandos nativos de macOS:

### 1. Sockets TCP en escucha

```bash
lsof -nP -iTCP -sTCP:LISTEN -Fpcn
```

Se usa para obtener:

- PID
- nombre corto del proceso
- sockets en escucha
- puerto y dirección detectada

### 2. Detalle del proceso

```bash
ps -ww -o pid=,ppid=,user=,etime=,args= -p <pid-list>
```

Se usa para obtener:

- comando completo
- usuario
- tiempo de ejecución aproximado

### 3. Carpeta de trabajo

```bash
lsof -a -d cwd -p <pid-list> -Fn
```

Se usa para inferir la carpeta del proyecto cuando el proceso lo permite.

## API local

### `GET /api/health`

Healthcheck simple.

### `GET /api/processes`

Devuelve JSON estructurado con:

- `processes`
- `summary`
- `warnings`
- `generatedAt`

### `POST /api/processes/:pid/terminate`

Body:

```json
{
  "force": false
}
```

Intenta `SIGTERM` primero. Si el proceso sigue vivo, la UI puede ofrecer forzar cierre.

### `POST /api/projects/terminate`

Body:

```json
{
  "cwd": "/ruta/del/proyecto",
  "force": false
}
```

Termina todos los procesos detectados con la misma carpeta de trabajo.

## Criterios cubiertos en esta primera versión

- Tabla con PID, proceso, comando, puertos, dirección, runtime, cwd y tipo estimado.
- Filtro rápido por PID, puerto, nombre, comando o carpeta.
- Refresh manual.
- Auto refresh cada pocos segundos.
- Botón para copiar comando.
- Botón para matar proceso.
- Acción para matar proyecto desde el detalle.
- Confirmación antes de cerrar procesos.
- `SIGTERM` primero, `SIGKILL` solo si hace falta.
- Exclusión explícita de los puertos `7000` y `7001` para no listar la propia herramienta.

## Validación hecha

Se probó el flujo real en macOS con:

- detección de un servidor Vite real
- detección de un backend Node real
- cierre de ambos usando el propio API del dashboard
- refresco posterior confirmando que desaparecieron de la lista

## Limitaciones conocidas

- La clasificación es heurística. Vite y Next son bastante confiables; otros servidores pueden quedar como `unknown`.
- Solo se consideran sockets TCP en estado `LISTEN`. No se muestran procesos que no estén escuchando puerto.
- Algunos procesos del sistema o apps protegidas pueden no exponer `cwd`, por lo que la carpeta puede salir como `desconocido`.
- El cierre de procesos depende de permisos del usuario actual. No intenta escalar privilegios.
- Si un proceso reutiliza puertos o expone múltiples sockets atípicos, la señalización de duplicados puede no ser perfecta.
- Esta primera versión está pensada para macOS; no está adaptada a Linux o Windows.

## Notas de uso

- Si ves varios procesos con la misma carpeta y tipo, revísalos como posible duplicidad.
- Si un proceso no cae con cierre normal, la UI te ofrece forzar el cierre.
- La herramienta no se expone fuera de localhost.
