# Kasir App API Documentation

## Overview

This document describes the Supabase API endpoints and data models used in the Kasir App. All requests require authentication unless specified otherwise.

## Base URL

```
https://[YOUR-PROJECT-ID].supabase.co
```

## Authentication

### Headers

```http
Authorization: Bearer <access_token>
apikey: <anon_key>
```

## Data Models

### User

```typescript
{
  id: UUID,
  email: string,
  full_name: string,
  role: 'admin' | 'manajer' | 'kasir',
  created_at: timestamp,
  updated_at: timestamp
}
```

### Store

```typescript
{
  id: UUID,
  name: string,
  address: string?,
  contact: string?,
  admin_id: UUID,
  created_at: timestamp,
  updated_at: timestamp
}
```

### Product

```typescript
{
  id: UUID,
  store_id: UUID,
  name: string,
  category: string?,
  price: decimal,
  stock: integer,
  image_url: string?,
  created_at: timestamp,
  updated_at: timestamp
}
```

### Transaction

```typescript
{
  id: UUID,
  store_id: UUID,
  user_id: UUID,
  customer_id: UUID?,
  total_amount: decimal,
  discount: decimal,
  tax: decimal,
  payment_method: 'cash' | 'card' | 'transfer',
  status: 'pending' | 'completed' | 'cancelled',
  transaction_date: timestamp,
  created_at: timestamp,
  updated_at: timestamp
}
```

### Customer

```typescript
{
  id: UUID,
  name: string,
  telephone: string?,
  note: string?,
  created_at: timestamp,
  updated_at: timestamp
}
```

### Subscription

```typescript
{
  id: UUID,
  user_id: UUID,
  package: 'Basic' | 'Pro' | 'Premium',
  start_date: timestamp,
  end_date: timestamp,
  status: 'active' | 'expired' | 'cancelled',
  created_at: timestamp,
  updated_at: timestamp
}
```

## Endpoints

### Authentication

#### Sign Up
```http
POST /auth/v1/signup
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword",
  "full_name": "John Doe",
  "role": "kasir"
}
```

#### Sign In
```http
POST /auth/v1/token?grant_type=password
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword"
}
```

### Users

#### Get Current User
```http
GET /rest/v1/users?id=eq.{current_user_id}
```

#### Update User
```http
PATCH /rest/v1/users?id=eq.{user_id}
Content-Type: application/json

{
  "full_name": "Updated Name"
}
```

### Stores

#### List Stores
```http
GET /rest/v1/stores
```

#### Create Store
```http
POST /rest/v1/stores
Content-Type: application/json

{
  "name": "My Store",
  "address": "123 Main St",
  "contact": "+1234567890"
}
```

#### Update Store
```http
PATCH /rest/v1/stores?id=eq.{store_id}
Content-Type: application/json

{
  "name": "Updated Store Name"
}
```

### Products

#### List Products
```http
GET /rest/v1/products?store_id=eq.{store_id}
```

#### Create Product
```http
POST /rest/v1/products
Content-Type: application/json

{
  "store_id": "uuid",
  "name": "Product Name",
  "price": 99.99,
  "stock": 100
}
```

#### Update Stock
```http
PATCH /rest/v1/products?id=eq.{product_id}
Content-Type: application/json

{
  "stock": 95
}
```

### Transactions

#### Create Transaction
```http
POST /rest/v1/rpc/create_transaction
Content-Type: application/json

{
  "p_store_id": "uuid",
  "p_user_id": "uuid",
  "p_customer_id": "uuid",
  "p_items": [
    {
      "product_id": "uuid",
      "quantity": 2,
      "price": 99.99
    }
  ],
  "p_payment_method": "cash",
  "p_discount": 0,
  "p_tax": 11
}
```

#### List Transactions
```http
GET /rest/v1/transactions?store_id=eq.{store_id}
```

### Customers

#### List Customers
```http
GET /rest/v1/customers
```

#### Create Customer
```http
POST /rest/v1/customers
Content-Type: application/json

{
  "name": "John Doe",
  "telephone": "+1234567890"
}
```

### Subscriptions

#### Get Current Subscription
```http
GET /rest/v1/subscriptions?user_id=eq.{user_id}&status=eq.active
```

#### Create Subscription
```http
POST /rest/v1/subscriptions
Content-Type: application/json

{
  "user_id": "uuid",
  "package": "Pro",
  "start_date": "2023-12-20T00:00:00Z",
  "end_date": "2024-01-20T00:00:00Z"
}
```

## Error Responses

### Standard Error Format
```json
{
  "error": {
    "message": "Error message here",
    "code": "ERROR_CODE",
    "details": {}
  }
}
```

### Common Error Codes
- `401`: Unauthorized
- `403`: Forbidden
- `404`: Not Found
- `422`: Validation Error
- `429`: Too Many Requests
- `500`: Internal Server Error

## Rate Limiting

- 100 requests per minute per IP
- 1000 requests per hour per user
- Exceeded limits return 429 status code

## Best Practices

1. **Authentication**
   - Always store tokens securely
   - Refresh tokens before expiry
   - Log out on security-sensitive errors

2. **Error Handling**
   - Always check response status codes
   - Implement retry logic for network errors
   - Show user-friendly error messages

3. **Data Management**
   - Implement local caching
   - Use optimistic updates
   - Validate data before sending

4. **Security**
   - Never send plain passwords
   - Validate input client-side
   - Use HTTPS for all requests

## Testing

### Test Environment
```
https://[YOUR-PROJECT-ID].supabase.co
```

### Test Credentials
```
Email: test@example.com
Password: test123
```

## Support

For API support:
1. Check [Supabase Documentation](https://supabase.com/docs)
2. Join [Discord Community](https://discord.gg/your-invite)
3. Create GitHub Issue
