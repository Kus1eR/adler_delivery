export interface Admin {
  id: number
  username: string
  display_name: string | null
  is_active: boolean
  is_superadmin: boolean
  created_at: string
}

export interface AdminCreate {
  username: string
  password: string
  display_name?: string
}
