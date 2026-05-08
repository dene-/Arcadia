# Dialog Server

Local Node.js helper server for NPC dialog backend requests. This tool is not exported with the Godot game.

## Setup

Use Node.js 22 or newer.

```powershell
npm install
Copy-Item .env.example .env
npm run dev
```

Put local secrets and API keys in `.env`. Keep `.env.example`, `package.json`, and `package-lock.json` tracked.

## Scripts

- `npm run dev`: start with Node watch mode.
- `npm start`: start normally.

Ignored local output includes `node_modules/`, `.env`, debug logs, coverage, caches, and build folders.
