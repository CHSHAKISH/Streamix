// supabase/functions/push-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { create } from "https://deno.land/x/djwt@v2.8/mod.ts"

// Load the Service Account JSON from Secrets
const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
const serviceAccount = serviceAccountStr ? JSON.parse(serviceAccountStr) : null

async function getAccessToken() {
  if (!serviceAccount) throw new Error("Missing FIREBASE_SERVICE_ACCOUNT secret")

  const now = Math.floor(Date.now() / 1000)
  const claim = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  }

  const key = serviceAccount.private_key
  const jwt = await create({ alg: "RS256", typ: "JWT" }, claim, key)

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const data = await res.json()
  return data.access_token
}

serve(async (req) => {
  try {
    const { token, title, body, data } = await req.json()

    if (!token) {
        return new Response(JSON.stringify({ error: 'Missing token' }), { status: 400 })
    }

    const accessToken = await getAccessToken()
    const projectId = serviceAccount.project_id

    const message = {
      message: {
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: data || {},
        android: {
            priority: "high",
            notification: {
                channel_id: "high_importance_channel"
            }
        }
      },
    }

    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(message),
      }
    )

    const json = await res.json()
    return new Response(JSON.stringify(json), { headers: { "Content-Type": "application/json" } })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { "Content-Type": "application/json" } })
  }
})