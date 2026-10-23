// TypeScript frontend: sends orders to the Go API and shows the ones the worker saved.
// Compiled to plain JavaScript at build time (tsc) and served by nginx.

interface Order {
  id: number;
  item: string;
  quantity: number;
  created_at: string;
}

const form = document.querySelector<HTMLFormElement>("#order-form")!;
const list = document.querySelector<HTMLUListElement>("#orders")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;

async function loadOrders(): Promise<void> {
  const res = await fetch("/api/orders");
  if (!res.ok) {
    status.textContent = `Could not load orders (${res.status})`;
    return;
  }
  const orders: Order[] = await res.json();
  list.replaceChildren(
    ...orders.map((o) => {
      const li = document.createElement("li");
      li.textContent = `#${o.id}  ${o.item} × ${o.quantity}  (${new Date(o.created_at).toLocaleTimeString()})`;
      return li;
    }),
  );
}

form.addEventListener("submit", async (event: SubmitEvent) => {
  event.preventDefault();
  const data = new FormData(form);
  const body = { item: String(data.get("item")), quantity: Number(data.get("quantity")) };

  const res = await fetch("/api/orders", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  status.textContent = res.ok
    ? "Queued in NATS — the worker will save it in a moment"
    : `Error ${res.status}`;
  form.reset();
  setTimeout(loadOrders, 1500);
});

loadOrders();
setInterval(loadOrders, 5000);
