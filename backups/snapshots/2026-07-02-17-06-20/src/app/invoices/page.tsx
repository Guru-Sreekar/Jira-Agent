import { prisma } from '@/lib/prisma';
import Link from 'next/link';

export default async function InvoicesPage() {
  const invoices = await prisma.invoice.findMany({
    include: { client: true },
    orderBy: { createdAt: 'desc' }
  });

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--spacing-6)' }}>
        <h1 className="text-h1" style={{ marginBottom: 0 }}>Invoices</h1>
        <Link href="/invoices/new" className="btn btn-primary">
          Create Invoice
        </Link>
      </div>

      <div className="card">
        {invoices.length === 0 ? (
          <p className="text-muted">No invoices found. Create your first invoice.</p>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Invoice #</th>
                  <th>Client</th>
                  <th>Date</th>
                  <th>Total</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {invoices.map((invoice: any) => (
                  <tr key={invoice.id}>
                    <td style={{ fontWeight: 500 }}>{invoice.invoiceNumber}</td>
                    <td>{invoice.client.name}</td>
                    <td className="text-muted">{new Date(invoice.date).toLocaleDateString()}</td>
                    <td style={{ fontWeight: 600 }}>${invoice.total.toFixed(2)}</td>
                    <td>
                      <span className={`badge badge-${invoice.status.toLowerCase()}`}>
                        {invoice.status}
                      </span>
                    </td>
                    <td style={{ display: 'flex', gap: 'var(--spacing-2)' }}>
                      <Link href={`/invoices/${invoice.id}`} className="btn btn-secondary" style={{ padding: '0.25rem 0.5rem', fontSize: '0.875rem' }}>
                        View
                      </Link>
                      <Link href={`/invoices/${invoice.id}/edit`} className="btn btn-secondary" style={{ padding: '0.25rem 0.5rem', fontSize: '0.875rem' }}>
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
