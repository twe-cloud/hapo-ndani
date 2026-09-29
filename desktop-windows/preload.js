const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ndani', {
  // Participant identity for the optional rail. Not a licence — the app is free.
  participant: {
    load: () => ipcRenderer.invoke('participant:load'),
    save: (data) => ipcRenderer.invoke('participant:save', data),
  },
  // Models
  models: {
    list: () => ipcRenderer.invoke('models:list'),
    detect: () => ipcRenderer.invoke('models:detect'),
    download: (id) => ipcRenderer.invoke('models:download', id),
    downloadProgress: (id) => ipcRenderer.invoke('models:download-progress', id),
    smokeTest: (id) => ipcRenderer.invoke('models:smoke-test', id),
  },
  // Folders
  folders: {
    list: () => ipcRenderer.invoke('folders:list'),
    add: () => ipcRenderer.invoke('folders:add'),
    remove: (id) => ipcRenderer.invoke('folders:remove', id),
    readPreview: (id) => ipcRenderer.invoke('folders:read-preview', id),
  },
  // Ledger
  ledger: {
    list: () => ipcRenderer.invoke('ledger:list'),
  },
  // System
  system: {
    info: () => ipcRenderer.invoke('system:info'),
  },
  // Shell
  shell: {
    open: (url) => ipcRenderer.invoke('shell:open', url),
  },
  // Backend API
  api: {
    fetch: (endpoint, options) => ipcRenderer.invoke('api:fetch', endpoint, options),
  },
});
