import StatusBadge from './StatusBadge.jsx';
import DeliveryTimeline from './DeliveryTimeline.jsx';

function formatDate(dateStr) {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleString('fr-FR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

export default function TrackingCard({ parcel }) {
  return (
    <article className="tracking-card">
      <div className="card-header">
        <h2 className="tracking-code">{parcel.tracking_code}</h2>
        <StatusBadge status={parcel.status} />
      </div>

      <div className="card-meta">
        <div className="meta-item">
          <span className="meta-label">Destinataire</span>
          <span className="meta-value">{parcel.recipient_name}</span>
        </div>
        <div className="meta-item">
          <span className="meta-label">Adresse</span>
          <span className="meta-value">{parcel.recipient_address || '—'}</span>
        </div>
        <div className="meta-item">
          <span className="meta-label">Dernière mise à jour</span>
          <span className="meta-value">{formatDate(parcel.updated_at)}</span>
        </div>
        {parcel.notified_at && (
          <div className="meta-item">
            <span className="meta-label">Notification envoyée</span>
            <span className="meta-value">{formatDate(parcel.notified_at)}</span>
          </div>
        )}
      </div>

      <DeliveryTimeline status={parcel.status} />

      {parcel.status !== 'DELIVERED' && (
        <p className="refresh-hint">Actualisation automatique toutes les 10 secondes</p>
      )}
    </article>
  );
}
