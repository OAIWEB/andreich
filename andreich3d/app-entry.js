import { boot } from './andreich.js';
// Вид по умолчанию — кругляш; приложение может переключить через A.setVariant.
window.A = boot(document.getElementById('c'), { transparent: true, quality: 'app', variant: 'mini' });
