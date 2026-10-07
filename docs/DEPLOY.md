# Deploying SplitEase


### Backend → Render

1. Push your repo to GitHub
2. Go to [render.com](https://render.com) → New → Web Service
3. Connect your repo, set **Root Directory** to `backend`, **Environment** to `Docker`
4. Add all environment variables from `.env` (use your Render URL for `APP_BASE_URL`)

### Frontend → Netlify

1. Point the app at your backend: `flutter build web --dart-define=API_BASE_URL=https://<your-render-app>.onrender.com/api`
   (or change `_productionUrl` in `frontend/lib/services/api_service.dart`)
2. Drag the `frontend/build/web/` folder to [netlify.com](https://netlify.com)
