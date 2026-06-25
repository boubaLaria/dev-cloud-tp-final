const LABELS = {
  PENDING:           { label: 'En attente',          icon: '🕐' },
  IN_TRANSIT:        { label: 'En transit',           icon: '🚚' },
  OUT_FOR_DELIVERY:  { label: 'En cours de livraison', icon: '📍' },
  DELIVERED:         { label: 'Livré',                icon: '✅' },
};

export default function StatusBadge({ status }) {
  const { label, icon } = LABELS[status] ?? { label: status, icon: '📦' };
  return (
    <span className={`status-badge ${status}`} role="status" aria-label={label}>
      <span aria-hidden="true">{icon}</span> {label}
    </span>
  );
}
