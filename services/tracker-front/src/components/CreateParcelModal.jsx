import { useState } from 'react';
import { createParcel } from '../services/parcelApi.js';

const DEFAULTS = {
  senderName: 'Bob Dupont',
  recipientName: 'Alice Martin',
  recipientEmail: 'alice@example.com',
  recipientAddress: "Place de l'Opéra, Paris",
  recipientLat: '48.8698',
  recipientLng: '2.3322',
};

export default function CreateParcelModal({ onCreated, onClose }) {
  const [form, setForm] = useState(DEFAULTS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const set = (field) => (e) => setForm((f) => ({ ...f, [field]: e.target.value }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const parcel = await createParcel({
        ...form,
        recipientLat: parseFloat(form.recipientLat),
        recipientLng: parseFloat(form.recipientLng),
      });
      onCreated(parcel);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">Créer un colis</h2>
          <button className="modal-close" onClick={onClose} aria-label="Fermer">✕</button>
        </div>

        <form onSubmit={handleSubmit} className="modal-form">
          <div className="modal-row">
            <label className="modal-label">Expéditeur</label>
            <input className="modal-input" value={form.senderName} onChange={set('senderName')} required />
          </div>
          <div className="modal-row">
            <label className="modal-label">Destinataire</label>
            <input className="modal-input" value={form.recipientName} onChange={set('recipientName')} required />
          </div>
          <div className="modal-row">
            <label className="modal-label">Email destinataire</label>
            <input className="modal-input" type="email" value={form.recipientEmail} onChange={set('recipientEmail')} required />
          </div>
          <div className="modal-row">
            <label className="modal-label">Adresse de livraison</label>
            <input className="modal-input" value={form.recipientAddress} onChange={set('recipientAddress')} required />
          </div>
          <div className="modal-row modal-row-split">
            <div>
              <label className="modal-label">Latitude</label>
              <input className="modal-input" type="number" step="any" value={form.recipientLat} onChange={set('recipientLat')} required />
            </div>
            <div>
              <label className="modal-label">Longitude</label>
              <input className="modal-input" type="number" step="any" value={form.recipientLng} onChange={set('recipientLng')} required />
            </div>
          </div>

          {error && <p className="modal-error">{error}</p>}

          <button className="modal-submit" type="submit" disabled={loading}>
            {loading ? 'Création…' : 'Créer le colis'}
          </button>
        </form>
      </div>
    </div>
  );
}
