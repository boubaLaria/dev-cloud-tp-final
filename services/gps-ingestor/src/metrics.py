from prometheus_client import Counter

POSITIONS_TOTAL = Counter(
    "gps_positions_total",
    "Total GPS positions successfully ingested",
)

POSITIONS_ERRORS = Counter(
    "gps_positions_errors_total",
    "Total GPS ingest errors (broker unavailable)",
)
