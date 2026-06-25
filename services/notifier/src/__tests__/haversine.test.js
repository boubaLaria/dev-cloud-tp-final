'use strict';
const { distanceMeters } = require('../services/haversine');

describe('distanceMeters', () => {
  it('retourne ~4.5km entre Tour Eiffel et Notre-Dame', () => {
    // Tour Eiffel: 48.8584, 2.2945 — Notre-Dame: 48.8530, 2.3499
    const dist = distanceMeters(48.8584, 2.2945, 48.8530, 2.3499);
    expect(dist).toBeGreaterThan(4000);
    expect(dist).toBeLessThan(5000);
  });

  it('retourne ~0m pour le même point', () => {
    const dist = distanceMeters(48.8566, 2.3522, 48.8566, 2.3522);
    expect(dist).toBeLessThan(1);
  });

  it('détecte correctement une distance < 2000m', () => {
    // Points séparés de ~500m
    const dist = distanceMeters(48.8566, 2.3522, 48.8610, 2.3522);
    expect(dist).toBeLessThan(2000);
    expect(dist).toBeGreaterThan(0);
  });
});
