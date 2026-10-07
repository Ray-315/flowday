import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './styles.css';
import './production.css';
import './ui.css';
import './select.css';
import './mobile.css';
import { initializeStorage } from './storage';

await initializeStorage();
ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
