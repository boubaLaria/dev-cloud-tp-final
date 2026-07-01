const BASE = import.meta.env.VITE_API_URL ?? '/api';

export async function createParcel(data) {
  const res = await fetch(`${BASE}/parcels`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail ? JSON.stringify(err.detail) : 'Erreur lors de la création');
  }
  return res.json();
}

export async function fetchParcel(trackingCode) {
  const res = await fetch(`${BASE}/parcels?trackingCode=${encodeURIComponent(trackingCode)}`);

  if (res.status === 404) {
    throw new Error(`Colis introuvable pour le numéro ${trackingCode}`);
  }
  if (!res.ok) {
    throw new Error('Service temporairement indisponible. Réessayez dans quelques instants.');
  }

  const data = await res.json();
  return data;
}
