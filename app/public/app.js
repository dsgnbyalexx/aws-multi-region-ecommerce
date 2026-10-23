const productsEl = document.getElementById('products');
const messageEl = document.getElementById('message');
const healthEl = document.getElementById('health');

const money = (cents) => `$${(cents / 100).toFixed(2)}`;

async function checkReady() {
  try {
    const res = await fetch('/ready');
    healthEl.textContent = res.ok ? 'API + database: ready' : 'database unavailable';
    healthEl.className = `badge ${res.ok ? 'ok' : 'bad'}`;
  } catch {
    healthEl.textContent = 'API unreachable';
    healthEl.className = 'badge bad';
  }
}

async function loadProducts() {
  const res = await fetch('/api/products');
  const { products } = await res.json();
  productsEl.replaceChildren(...products.map(renderProduct));
}

function renderProduct(p) {
  const card = document.createElement('article');
  card.className = 'card';
  const title = document.createElement('h2');
  title.textContent = p.name;
  const desc = document.createElement('p');
  desc.textContent = p.description;
  const row = document.createElement('div');
  row.className = 'row';
  const price = document.createElement('span');
  price.className = 'price';
  price.textContent = money(p.priceCents);
  const stock = document.createElement('span');
  stock.className = 'stock';
  stock.textContent = `${p.stock} in stock`;
  row.append(price, stock);
  const button = document.createElement('button');
  button.textContent = p.stock > 0 ? 'Buy 1' : 'Sold out';
  button.disabled = p.stock === 0;
  button.addEventListener('click', () => buy(p.id, button));
  card.append(title, desc, row, button);
  return card;
}

async function buy(productId, button) {
  button.disabled = true;
  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ customerEmail: 'demo@example.com', items: [{ productId, quantity: 1 }] }),
  });
  const body = await res.json();
  messageEl.textContent = res.ok
    ? `Order #${body.order.id} confirmed: ${money(body.order.totalCents)}`
    : `Order failed: ${body.error}`;
  await loadProducts();
}

checkReady();
loadProducts().catch(() => { messageEl.textContent = 'Could not load products.'; });
