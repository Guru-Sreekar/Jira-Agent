'use client';

import { createInvoice, updateInvoice, deleteInvoice } from '@/app/actions/invoice';
import { useState, useEffect } from 'react';
import { Plus, Trash2 } from 'lucide-react';

type InvoiceFormProps = {
  clients: { id: string, name: string }[];
  invoice?: any; // To keep it simple, any for now
};

export default function InvoiceForm({ clients, invoice }: InvoiceFormProps) {
  const [isDeleting, setIsDeleting] = useState(false);
  const [items, setItems] = useState(invoice?.items || [{ description: '', quantity: 1, price: 0 }]);
  const [taxRate, setTaxRate] = useState<string>(() => {
    if (invoice && invoice.subtotal > 0 && invoice.tax >= 0) {
      const rate = (invoice.tax / invoice.subtotal) * 100;
      if (isFinite(rate)) {
        return rate.toFixed(2);
      }
    }
    return '0';
  });

  const addItem = () => {
    setItems([...items, { description: '', quantity: 1, price: 0 }]);
  };

  const removeItem = (index: number) => {
    setItems(items.filter((_: any, i: number) => i !== index));
  };

  const handleItemChange = (index: number, field: string, value: string | number) => {
    const newItems = [...items];
    if (field === 'quantity' || field === 'price') {
      newItems[index] = { ...newItems[index], [field]: Number(value) };
    } else {
      newItems[index] = { ...newItems[index], [field]: value };
    }
    setItems(newItems);
  };

  // Calculate accurate subtotal by reducing items
  const rawSubtotal = items.reduce((sum: number, item: any) => sum + (item.quantity * item.price), 0);
  const subtotal = Math.round(rawSubtotal * 100) / 100;
  
  // Calculate accurate tax to 2 decimals to avoid floating point issues (e.g. 0.1 + 0.2)
  const taxPercent = isNaN(Number(taxRate)) ? 0 : Number(taxRate) / 100;
  const tax = Math.round((subtotal * taxPercent) * 100) / 100;
  
  // Final total
  const total = Math.round((subtotal + tax) * 100) / 100;

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    formData.append('taxRate', taxRate.toString());

    if (invoice) {
      await updateInvoice(invoice.id, formData);
    } else {
      await createInvoice(formData);
    }
  };

  return (
    <div className="card glass-panel" style={{ maxWidth: '800px' }}>
      <h2 className="text-h2" style={{ marginBottom: 'var(--spacing-6)' }}>
        {invoice ? 'Edit Invoice' : 'Create Invoice'}
      </h2>

      <form onSubmit={handleSubmit}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--spacing-4)' }}>
          <div className="form-group">
            <label htmlFor="invoiceNumber" className="form-label">Invoice Number *</label>
            <input type="text" id="invoiceNumber" name="invoiceNumber" className="input-field" defaultValue={invoice?.invoiceNumber} required />
          </div>

          <div className="form-group">
            <label htmlFor="clientId" className="form-label">Client *</label>
            <select id="clientId" name="clientId" className="input-field" defaultValue={invoice?.clientId} required>
              <option value="">Select a client</option>
              {clients.map(client => (
                <option key={client.id} value={client.id}>{client.name}</option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label htmlFor="date" className="form-label">Date *</label>
            <input type="date" id="date" name="date" className="input-field" defaultValue={invoice?.date ? new Date(invoice.date).toISOString().split('T')[0] : ''} required />
          </div>

          <div className="form-group">
            <label htmlFor="dueDate" className="form-label">Due Date *</label>
            <input type="date" id="dueDate" name="dueDate" className="input-field" defaultValue={invoice?.dueDate ? new Date(invoice.dueDate).toISOString().split('T')[0] : ''} required />
          </div>

          <div className="form-group">
            <label htmlFor="status" className="form-label">Status *</label>
            <select id="status" name="status" className="input-field" defaultValue={invoice?.status || 'DRAFT'} required>
              <option value="DRAFT">Draft</option>
              <option value="PENDING">Pending</option>
              <option value="PAID">Paid</option>
              <option value="OVERDUE">Overdue</option>
            </select>
          </div>
        </div>

        <div style={{ marginTop: 'var(--spacing-6)', marginBottom: 'var(--spacing-4)' }}>
          <h3 className="text-h3">Line Items</h3>

          <table className="table" style={{ marginTop: 'var(--spacing-2)' }}>
            <thead>
              <tr>
                <th>Description</th>
                <th style={{ width: '100px' }}>Qty</th>
                <th style={{ width: '150px' }}>Price</th>
                <th style={{ width: '150px' }}>Total</th>
                <th style={{ width: '60px' }}></th>
              </tr>
            </thead>
            <tbody>
              {items.map((item: any, index: number) => (
                <tr key={index}>
                  <td>
                    <input type="text" className="input-field" value={item.description} onChange={(e) => handleItemChange(index, 'description', e.target.value)} required placeholder="Item description" />
                  </td>
                  <td>
                    <input type="number" className="input-field" value={item.quantity} onChange={(e) => handleItemChange(index, 'quantity', parseInt(e.target.value) || 0)} min="1" required />
                  </td>
                  <td>
                    <input type="number" className="input-field" value={item.price} onChange={(e) => handleItemChange(index, 'price', parseFloat(e.target.value) || 0)} min="0" step="0.01" required />
                  </td>
                  <td style={{ verticalAlign: 'middle', fontWeight: 500 }}>
                    ${(item.quantity * item.price).toFixed(2)}
                  </td>
                  <td style={{ verticalAlign: 'middle' }}>
                    <button type="button" onClick={() => removeItem(index)} className="btn btn-secondary" style={{ padding: '0.25rem 0.5rem' }} aria-label="Remove item">
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <button type="button" onClick={addItem} className="btn btn-secondary" style={{ marginTop: 'var(--spacing-3)' }}>
            <Plus size={16} /> Add Item
          </button>
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 'var(--spacing-6)' }}>
          <div style={{ width: '300px', background: 'var(--surface-hover)', padding: 'var(--spacing-4)', borderRadius: 'var(--radius-md)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 'var(--spacing-2)' }}>
              <span>Subtotal:</span>
              <span>${subtotal.toFixed(2)}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 'var(--spacing-2)', alignItems: 'center' }}>
              <span>Tax Rate (%):</span>
              <input type="number" className="input-field" value={taxRate} onChange={(e) => setTaxRate(e.target.value)} style={{ width: '80px', padding: '0.25rem' }} min="0" step="0.1" />
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 'var(--spacing-2)' }}>
              <span>Tax Amount:</span>
              <span>${tax.toFixed(2)}</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid var(--border)', paddingTop: 'var(--spacing-2)', marginTop: 'var(--spacing-2)', fontWeight: 700, fontSize: '1.25rem' }}>
              <span>Total:</span>
              <span style={{ color: 'var(--primary)' }}>${total.toFixed(2)}</span>
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', gap: 'var(--spacing-4)', marginTop: 'var(--spacing-8)' }}>
          <button type="submit" className="btn btn-primary">
            {invoice ? 'Update Invoice' : 'Save Invoice'}
          </button>
          <a href="/invoices" className="btn btn-secondary">Cancel</a>

          {invoice && (
            <button
              type="button"
              className="btn btn-danger"
              style={{ marginLeft: 'auto' }}
              onClick={async () => {
                if (confirm('Are you sure you want to delete this invoice?')) {
                  setIsDeleting(true);
                  await deleteInvoice(invoice.id);
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
