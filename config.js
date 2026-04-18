// Supabase Configuration
// TODO: Replace with your actual Supabase project URL and ANON KEY before running locally.
const SUPABASE_URL = 'YOUR_SUPABASE_URL_HERE';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY_HERE';
// Initialize Supabase client
window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
// Role → dashboard mapping
const ROLE_MAP = {
    'STUDENT': 'student.html',
    'WARDEN':  'warden.html',
    'GUARD':   'guard.html'
};
const Auth = {
    // Call this on login success — saves user and redirects to their dashboard
    login: (user) => {
        localStorage.setItem('currentUser', JSON.stringify(user));
        const dest = ROLE_MAP[user.role];
        if (dest) {
            window.location.href = dest;
        } else {
            alert('Unknown role: ' + user.role);
        }
    },
    // Clears session and returns to login page
    logout: () => {
        localStorage.removeItem('currentUser');
        window.location.href = 'index.html';
    },
    // Returns the stored user object, or null if not logged in (NO redirect side-effect)
    getCurrentUser: () => {
        const userStr = localStorage.getItem('currentUser');
        if (!userStr) return null;
        try {
            return JSON.parse(userStr);
        } catch (e) {
            localStorage.removeItem('currentUser');
            return null;
        }
    },
    // Call this at the top of each dashboard page.
    // If no session → go to login.
    // If wrong role → silently go to the correct dashboard (no alert, no loop).
    requireRole: (role) => {
        const user = Auth.getCurrentUser();
        // No session at all → go to login
        if (!user) {
            window.location.href = 'index.html';
            return null;
        }
        // Logged in, but wrong page for this role → go to the correct dashboard
        if (user.role !== role) {
            const dest = ROLE_MAP[user.role] || 'index.html';
            window.location.href = dest;
            return null;
        }
        // All good — return the user
        return user;
    }
};
