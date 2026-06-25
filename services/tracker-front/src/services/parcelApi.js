const BASE = import.meta.env.VITE_API_URL ?? '/api';

export async function fetchParcel(trackingCode) {
  const res = await fetch(`${BASE}/parcels?trackingCode=${encodeURIComponent(trackingCode)}`);

  if (res.status === 404) {
    throw new Error(`Colis introuvable pour le numéro ${trackingCode}`);
  }
  if (!res.ok) {
    throw new Error('Service temporairement indisponible. Réessayez dans quelques instants.');
  }

  const data = await res.json();
  // parcel-api renvoie un tableau pour la recherche par trackingCode
  const parcel = Array.isArray(data) ? data[0] : data;
  if (!parcel) {
    throw new Error(`Colis introuvable pour le numéro ${trackingCode}`);
  }
  return parcel;
}
