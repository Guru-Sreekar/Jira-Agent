import { prisma } from '@/lib/prisma';

export default async function Home() {
  const invoiceCount = await prisma.invoice.count();
  const clientCount = await prisma.client.count();

  // For a real app, you'd calculate total revenue by summing up 'total' of 'PAID' invoices
  const paidInvoices = await prisma.invoice.aggregate({
    _sum: { total: true },
    where: { status: 'COMPLETED' },
  });
  
  const pendingInvoices = await prisma.invoice.aggregate({
    _sum: { total: true },
    where: { status: 'PENDING' },
  });

  const totalRevenue = paidInvoices._sum.total || 0;
  const totalPending = pendingInvoices._sum.total || 0;

  return (
    <div>
      <h1 className="text-h1">Dashboard</h1>
      <p className="text-muted" style={{ marginBottom: 'var(--spacing-8)' }}>
        Welcome to your InvoiceApp dashboard. Here's an overview of your business.
      </p>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 'var(--spacing-6)', marginBottom: 'var(--spacing-10)' }}>
        <div className="card glass-panel">
          <h3 className="text-h3">Total Revenue</h3>
          <p className="text-h1" style={{ color: 'var(--primary)', marginBottom: 0 }}>
            ${totalRevenue.toFixed(2)}
          </p>
        </div>
        <div className="card glass-panel">
          <h3 className="text-h3">Outstanding</h3>
          <p className="text-h1" style={{ color: '#D97706', marginBottom: 0 }}>
            ${totalPending.toFixed(2)}
          </p>
        </div>
        <div className="card glass-panel">
          <h3 className="text-h3">Total Invoices</h3>
          <p className="text-h1" style={{ marginBottom: 0 }}>
            {invoiceCount}
          </p>
        </div>
        <div className="card glass-panel">
          <h3 className="text-h3">Total Clients</h3>
          <p className="text-h1" style={{ marginBottom: 0 }}>
            {clientCount}
          </p>
        </div>
      </div>
      
      <div className="card">
        <h2 className="text-h2">Recent Activity</h2>
        <p className="text-muted">No recent activity to display yet. Start by adding a client or creating an invoice.</p>
        <div style={{ marginTop: 'var(--spacing-4)', display: 'flex', gap: 'var(--spacing-4)' }}>
          <a href="/clients/new" className="btn btn-primary">Add Client</a>
          <a href="/invoices/new" className="btn btn-secondary">Create Invoice</a>
        </div>
      </div>
    </div>
  );
}
