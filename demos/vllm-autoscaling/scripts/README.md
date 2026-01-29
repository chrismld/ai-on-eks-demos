# Demo Scripts

This directory contains all the scripts needed to run the interactive Tube Scaling Demo.

## Demo Flow (30 minutes)

### Phase 1: Audience Engagement (0-2 minutes)
1. Show QR code pointing to the frontend ALB URL
2. Audience scans and submits ONE question about the London Underground
3. Questions are stored and will be amplified 50x

### Phase 2: Live Demo + Presentation (2-25 minutes)
4. Run `make run-demo` to start:
   - Amplified load generator (replays audience questions 50x)
   - Terminal dashboard showing real-time scaling
5. Present while the dashboard shows live metrics
6. Audience sees their contribution on their phones

### Phase 3: Survey (25-28 minutes)
7. Run `make enable-survey` to switch to survey mode
8. Audience rates the session and enters raffle
9. Responses stored in S3

### Phase 4: Raffle (28-30 minutes)
10. Run `make pick-winners` to select 2 random winners
11. Winners see congratulations message on their phones
12. Everyone else sees thank you message

## Scripts

### `run-demo.sh`
Main demo orchestration script that:
- Gets the frontend ALB URL
- Sets up port-forwards for API and OTEL scaler
- Starts the amplified load generator
- Launches the terminal dashboard

Usage:
```bash
make run-demo
# or
bash scripts/run-demo.sh
```

### `dashboard.sh`
Real-time terminal dashboard showing:
- Queue depth with progress bar
- Pod count with Tube line names
- GPU node count
- Audience contribution stats
- Speaker stress level (emoji-based)
- Live commentary (self-deprecating humor)
- Latest scaling events
- Demo progress timer

The dashboard includes a fun commentary system that makes jokes about the speakers based on the current scaling state. Messages change dynamically based on queue depth, pod count, and scaling efficiency.

Usage:
```bash
make dashboard
# or
bash scripts/dashboard.sh
```

### `amplified-load-gen.js`
k6 load generator that:
- Fetches audience questions from API every 10 seconds
- Amplifies each question 50x (configurable via MULTIPLIER env var)
- Falls back to default Tube questions if no audience questions
- Runs for 30 minutes with staged load profile

Usage:
```bash
API_URL="http://localhost:8000" MULTIPLIER=50 k6 run scripts/amplified-load-gen.js
```

### `load-gen.js`
Original simple load generator (kept for reference):
- Sends requests to frontend URL
- Uses default Tube questions
- No amplification

### `enable-survey.sh`
Switches the demo mode from "quiz" to "survey":
```bash
make enable-survey
# or
bash scripts/enable-survey.sh
```

### `pick-winners.sh`
Selects 2 random winners from survey responses:
- Lists all responses from S3
- Randomly selects 2
- Writes winners.json to S3
- Frontend polls this file to show winner message

Usage:
```bash
make pick-winners
# or
bash scripts/pick-winners.sh
```

### `get-frontend-url.sh`
Helper script to retrieve the frontend ALB URL:
```bash
make get-frontend-url
# or
bash scripts/get-frontend-url.sh
```

### `build-images.sh`
Builds and pushes Docker images to ECR:
```bash
make build-push-images
# or
bash scripts/build-images.sh
```

### `teardown.sh`
Cleanup script that:
- Deletes all Kubernetes services
- Removes Karpenter resources
- Runs terraform destroy

Usage:
```bash
make teardown
# or
bash scripts/teardown.sh
```

## Environment Variables

### For `amplified-load-gen.js`:
- `API_URL`: API endpoint (default: http://localhost:8000)
- `MULTIPLIER`: Amplification factor (default: 50)

### For `run-demo.sh`:
- Automatically detects frontend URL from Ingress
- Falls back to localhost if ALB not ready

## Tips

1. **Test the dashboard first**: Run `make dashboard` to see if metrics are accessible
2. **Check port-forwards**: Ensure ports 8000 and 8080 are available
3. **Monitor logs**: Watch API logs with `kubectl logs -f deployment/api`
4. **Adjust multiplier**: Change MULTIPLIER in run-demo.sh if you need more/less load
5. **QR code generation**: Use any QR code generator with your ALB URL

## Troubleshooting

**Dashboard shows 0 pods:**
- Check if vLLM pods are running: `kubectl get pods -l app=vllm`
- Verify port-forward to OTEL scaler: `curl http://localhost:8080/metrics`

**No audience questions:**
- Check API logs: `kubectl logs -f deployment/api`
- Verify S3 bucket exists and has permissions
- Load generator will use default questions as fallback

**Winners not showing:**
- Ensure `pick-winners.sh` completed successfully
- Check S3 for winners.json file
- Verify frontend is polling `/api/survey/winners`
