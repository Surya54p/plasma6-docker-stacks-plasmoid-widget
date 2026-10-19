# Docker Compose Stacks Controller (KDE Plasma 6 Plasmoid)

A fast, lightweight, and standalone panel widget for **KDE Plasma 6** to monitor and manage Docker Compose stacks directly from your desktop panel.

![KDE Plasma 6](https://img.shields.io/badge/KDE-Plasma_6-blue.svg)
![Docker Compose](https://img.shields.io/badge/Docker-Compose_v2-2496ED.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

---

## ✨ Features

- **Panel Icon-Only Integration**: Compact and clean Docker icon on your KDE panel.
- **Stack-Level Grouping**: Controls your containers as stacks (e.g., `web`, `db`, `backend`), not fragmented individual containers.
- **Quick Controls**:
  - `▶` **Start**: Start all containers in the stack.
  - `■` **Stop**: Stop all containers in the stack.
  - `⟳` **Restart**: Restart all containers in the stack.
  - `📄` **Logs**: Live log viewer that automatically jumps to the latest log line.
- **Smart Filtering & Search**:
  - Filter by: **Aktif (Running/Partial)**, **Semua (All)**, and **Berhenti (Exited)**.
  - Default view focuses only on currently active stacks.
  - Instant search by stack name.
- **Zero Configuration & Standalone**:
  - Uses native `docker compose` CLI via KDE's native executable data source.
  - No background server, no Node/Python daemon, no Docker socket permission hurdles required.

---

## 🚀 Installation

### 1. Clone the repository
```bash
git clone https://github.com/surya54p/plasma6-docker-stacks-plasmoid.git
cd plasma6-docker-stacks-plasmoid
```

### 2. Install the Plasmoid
```bash
kpackagetool6 --type Plasma/Applet --install package/
```

*(If upgrading an existing installation, use `--upgrade package/`)*

### 3. Add to your Panel
1. Right-click on your KDE panel and select **Add or Manage Widgets...**
2. Search for **Docker Stacks Controller**.
3. Drag and drop the widget into your panel.

---

## 📋 Requirements
- **KDE Plasma 6** (`plasmashell >= 6.0`)
- **Docker & Docker Compose v2** (`docker compose` available in `$PATH`)
- Current user added to the `docker` group (`sudo usermod -aG docker $USER`)

---

## 📄 License
MIT License. Feel free to use, modify, and distribute.
