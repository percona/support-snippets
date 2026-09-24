FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates ./templates
COPY static ./static

# The /exercises folder is mounted read-only at runtime so the controller
# can read each level's README without rebuilding the controller image.
VOLUME ["/exercises", "/state"]

EXPOSE 5000
# One worker, many threads. The current level, the results and the locks
# that guard them all live in this one process; a second worker shares
# none of that, so two Sends in quick succession could each read the same
# level, grade the next question's still-booting container and skip it.
# The load is one candidate and one interviewer, and threads are enough to
# keep the slow Docker calls from blocking the dashboard poll.
CMD ["gunicorn", "-b", "0.0.0.0:5000", "-w", "1", "-k", "gthread", "--threads", "8", "--timeout", "420", "app:app"]
