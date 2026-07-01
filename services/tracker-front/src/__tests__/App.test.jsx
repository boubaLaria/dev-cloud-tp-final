import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { vi, describe, it, expect, beforeEach } from 'vitest';
import App from '../App.jsx';
import * as parcelApi from '../services/parcelApi.js';

vi.mock('../services/parcelApi.js');

const MOCK_PARCEL = {
  id: 'uuid-1',
  tracking_code: 'GL-4F2A8C',
  status: 'IN_TRANSIT',
  recipient_name: 'Bob Martin',
  recipient_address: '12 rue de la Paix, Paris',
  updated_at: '2026-06-25T10:00:00Z',
  notified_at: null,
};

describe('App — Tracker Front', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('affiche le champ de recherche au chargement', () => {
    render(<App />);
    expect(screen.getByRole('search')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('GL-4F2A8C')).toBeInTheDocument();
  });

  it('affiche la carte de suivi après une recherche réussie', async () => {
    parcelApi.fetchParcel.mockResolvedValueOnce(MOCK_PARCEL);
    render(<App />);

    fireEvent.change(screen.getByPlaceholderText('GL-4F2A8C'), {
      target: { value: 'GL-4F2A8C' },
    });
    fireEvent.click(screen.getByText('Suivre'));

    await waitFor(() => {
      expect(screen.getByText('GL-4F2A8C')).toBeInTheDocument();
      expect(screen.getByText('Bob Martin')).toBeInTheDocument();
      // Le badge status a un rôle "status" avec aria-label
      expect(screen.getByRole('status', { name: 'En transit' })).toBeInTheDocument();
    });
  });

  it("affiche un message d'erreur si le colis est introuvable", async () => {
    parcelApi.fetchParcel.mockRejectedValueOnce(
      new Error('Colis introuvable pour le numéro GL-XXXXXX')
    );
    render(<App />);

    fireEvent.change(screen.getByPlaceholderText('GL-4F2A8C'), {
      target: { value: 'GL-XXXXXX' },
    });
    fireEvent.click(screen.getByText('Suivre'));

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('Colis introuvable');
    });
  });

  it('convertit le code en majuscules avant la recherche', async () => {
    parcelApi.fetchParcel.mockResolvedValueOnce(MOCK_PARCEL);
    render(<App />);

    fireEvent.change(screen.getByPlaceholderText('GL-4F2A8C'), {
      target: { value: 'gl-4f2a8c' },
    });
    fireEvent.click(screen.getByText('Suivre'));

    await waitFor(() => {
      expect(parcelApi.fetchParcel).toHaveBeenCalledWith('GL-4F2A8C');
    });
  });

  it('désactive le bouton pendant le chargement', async () => {
    parcelApi.fetchParcel.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve(MOCK_PARCEL), 100))
    );
    render(<App />);

    fireEvent.change(screen.getByPlaceholderText('GL-4F2A8C'), {
      target: { value: 'GL-4F2A8C' },
    });
    fireEvent.click(screen.getByText('Suivre'));

    expect(screen.getByRole('button', { name: /recherche/i })).toBeDisabled();
    await waitFor(() => expect(screen.getByText('GL-4F2A8C')).toBeInTheDocument());
  });
});
