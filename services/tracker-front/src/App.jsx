import { useState, useEffect, useCallback } from 'react';
import SearchBox from './components/SearchBox.jsx';
import TrackingCard from './components/TrackingCard.jsx';
import { fetchParcel } from './services/parcelApi.js';

export default function App() {
  const [trackingCode, setTrackingCode] = useState('');
  const [parcel, setParcel] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  const search = useCallback(async (code) => {
    if (!code.trim()) return;
    setLoading(true);
    setError(null);
    setParcel(null);
    try {
      const data = await fetchParcel(code.trim().toUpperCase());
      setParcel(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  // Auto-refresh toutes les 10s tant que non livré
  useEffect(() => {
    if (!parcel || parcel.status === 'DELIVERED') return;
    const timer = setInterval(() => search(parcel.tracking_code), 10000);
    return () => clearInterval(timer);
  }, [parcel, search]);

  const handleSubmit = (code) => {
    setTrackingCode(code);
    search(code);
  };

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <span className="logo">
            <span className="logo-leaf">🌿</span> GreenLogistics
          </span>
          <span className="tagline">Suivi de livraison temps réel</span>
        </div>
      </header>

      <main className="main">
        <div className="hero">
          <h1 className="hero-title">Où est votre colis&nbsp;?</h1>
          <p className="hero-sub">
            Entrez votre numéro de suivi pour localiser votre livraison
          </p>
          <SearchBox onSearch={handleSubmit} loading={loading} />
        </div>

        {error && (
          <div className="alert alert-error" role="alert">
            {error}
          </div>
        )}

        {parcel && <TrackingCard parcel={parcel} />}

        {!parcel && !error && !loading && (
          <div className="empty-state">
            <div className="empty-icon">📦</div>
            <p>Votre numéro de suivi commence par <strong>GL-</strong></p>
            <p className="hint">Exemple&nbsp;: GL-4F2A8C</p>
          </div>
        )}
      </main>

      <footer className="footer">
        <p>GreenLogistics © 2026 — Livraison éco-responsable</p>
      </footer>
    </div>
  );
}
