FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim AS runner
RUN addgroup --system --gid 1001 appgroup \
 && adduser --system --uid 1001 --gid 1001 --ingroup appgroup appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY src ./src
USER appuser
EXPOSE 3001
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3001/health')" || exit 1
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "3001"]
