import { useState } from 'react';

export default function SearchBox({ onSearch, loading }) {
  const [value, setValue] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (value.trim()) onSearch(value.trim());
  };

  return (
    <form className="search-form" onSubmit={handleSubmit} role="search">
      <input
        className="search-input"
        type="text"
        placeholder="GL-4F2A8C"
        value={value}
        onChange={(e) => setValue(e.target.value.toUpperCase())}
        aria-label="Numéro de suivi"
        maxLength={10}
        autoComplete="off"
      />
      <button
        className="search-btn"
        type="submit"
        disabled={loading || !value.trim()}
        aria-busy={loading}
      >
        {loading ? 'Recherche…' : 'Suivre'}
      </button>
    </form>
  );
}
