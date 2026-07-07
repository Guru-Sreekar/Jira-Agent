import { prisma } from '@/lib/prisma';
import Link from 'next/link';

export default async function ClientsPage() {
  const clients = await prisma.client.findMany({
    orderBy: { createdAt: 'desc' }
  });

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--spacing-6)' }}>
        <h1 className="text-h1" style={{ marginBottom: 0 }}>Clients</h1>
        <Link href="/clients/new" className="btn btn-primary">
          Add Client
        </Link>
      </div>

      <div className="card">
        {clients.length === 0 ? (
          <p className="text-muted">No clients found. Add your first client to get started.</p>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Email</th>
                  <th>Phone</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {clients.map((client: any) => (
                  <tr key={client.id}>
                    <td style={{ fontWeight: 500 }}>{client.name}</td>
                    <td className="text-muted">{client.email || '-'}</td>
                    <td className="text-muted">{client.phone || '-'}</td>
                    <td>
                      <Link href={`/clients/${client.id}`} className="btn btn-secondary" style={{ padding: '0.25rem 0.5rem', fontSize: '0.875rem' }}>
                        Edit
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
