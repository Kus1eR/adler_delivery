export interface LoginRequest {
  username: string
  password: string
}

export interface LoginResponse {
  access_token: string
  token_type: string
  role: string
  user_id: number
}

export interface AuthState {
  token: string | null
  role: string | null
  userId: number | null
  isAuthenticated: boolean
}