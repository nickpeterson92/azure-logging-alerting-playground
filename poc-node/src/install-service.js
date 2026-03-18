const path = require('node:path');
const Service = require('node-windows').Service;

const svc = new Service({
  name: 'SQLSync Node Simulator',
  description: 'SQL Server to Salesforce data sync failure simulator',
  script: path.join(__dirname, 'index.js'),
  nodeOptions: []
});

svc.on('install', () => {
  console.log('Service installed successfully. Starting...');
  svc.start();
});

svc.on('alreadyinstalled', () => {
  console.log('Service is already installed.');
});

svc.on('error', (err) => {
  console.error('Service error:', err);
});

svc.install();
