'use client';

import { createClient, updateClient, deleteClient } from '@/app/actions/client';
import { useActionState, useState } from 'react';

type ClientFormProps = {
  client?: {
    id: string;
    name: string;
    email: string | null;
    phone: string | null;
    address: string | null;
  };
};

export default function ClientForm({ client }: ClientFormProps) {
  const [isDeleting, setIsDeleting] = useState(false);

  // We can just use standard form action with Next.js 15
  const action = client ? updateClient.bind(null, client.id) : createClient;

  return (
    <div className="card glass-panel" style={{ maxWidth: '600px' }}>
      <h2 className="text-h2" style={{ marginBottom: 'var(--spacing-6)' }}>
        {client ? 'Edit Client' : 'New Client'}
      </h2>

      <form action={action}>
        <div className="form-group">
          <label htmlFor="name" className="form-label">Name *</label>
          <input type="text" id="name" name="name" className="input-field" defaultValue={client?.name} required />
        </div>

        <div className="form-group">
          <label htmlFor="email" className="form-label">Email</label>
          <input type="email" id="email" name="email" className="input-field" defaultValue={client?.email || ''} />
        </div>

        <div className="form-group">
          <label htmlFor="phone" className="form-label">Phone</label>
          <input type="tel" id="phone" name="phone" className="input-field" defaultValue={client?.phone || ''} />
        </div>

        <div className="form-group">
          <label htmlFor="address" className="form-label">Address</label>
          <textarea id="address" name="address" className="input-field" rows={3} defaultValue={client?.address || ''}></textarea>
        </div>

        <div style={{ display: 'flex', gap: 'var(--spacing-4)', marginTop: 'var(--spacing-6)' }}>
          <button type="submit" className="btn btn-primary">
            {client ? 'Update Client' : 'Save Client'}
          </button>
          <a href="/clients" className="btn btn-secondary">Cancel</a>

          {client && (
            <button
              type="button"
              className="btn btn-danger"
              style={{ marginLeft: 'auto' }}
              onClick={async () => {
                if (confirm('Are you sure you want to delete this client?')) {
                  setIsDeleting(true);
                  try {
                    const res = await deleteClient(client.id);
                    if (res?.error) {
                      alert(res.error);
                      setIsDeleting(false);
                    }
                  } catch (error: any) {
                    alert('An unexpected error occurred.');
                    setIsDeleting(false);
                  }
                }
              }}
              disabled={isDeleting}
            >
              {isDeleting ? 'Deleting...' : 'Delete'}
            </button>
          )}
        </div>
      </form>
    </div>
  );
}
