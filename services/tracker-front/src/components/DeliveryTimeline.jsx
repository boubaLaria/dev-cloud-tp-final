const STEPS = [
  { status: 'PENDING',          label: 'Commande prise en charge' },
  { status: 'IN_TRANSIT',       label: 'En transit' },
  { status: 'OUT_FOR_DELIVERY', label: 'En cours de livraison' },
  { status: 'DELIVERED',        label: 'Livré' },
];

const ORDER = ['PENDING', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED'];

export default function DeliveryTimeline({ status }) {
  const currentIndex = ORDER.indexOf(status);

  return (
    <ol className="timeline" aria-label="Étapes de livraison">
      {STEPS.map((step, i) => {
        const isDone = i < currentIndex;
        const isActive = i === currentIndex;
        const dotClass = isDone ? 'done' : isActive ? 'active' : '';
        const labelClass = isDone ? 'done' : isActive ? 'active' : '';

        return (
          <li key={step.status} className="timeline-step">
            <span className={`step-dot ${dotClass}`} aria-hidden="true" />
            <span className={`step-label ${labelClass}`}>{step.label}</span>
          </li>
        );
      })}
    </ol>
  );
}
