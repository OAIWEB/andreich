import { boot } from './andreich.js';
// Кругляш по умолчанию; мех жёсткий — без полупрозрачности поверх светлых окон.
window.A = boot(document.getElementById('c'), { transparent: true, quality: 'app', variant: 'mini', hardFur: true });
