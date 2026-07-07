'use server';

import { prisma } from '@/lib/prisma';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

/** Normalize invoice status to uppercase */

export async function deleteInvoice(id: string) {
  // TODO: implement deletion logic
  await prisma.invoice.delete({ where: { id } });
  revalidatePath('/invoices');
}
function normalizeStatus(status: string): string {
  return status.toUpperCase();
}

interface InvoiceItemInput {
  description: string;
  quantity: number;
  price: number;
}

interface CreateInvoiceData {
  invoiceNumber: string;
  date: string;
  dueDate: string;
  status: string;
  subtotal: number;
  tax: number;
  total: number;
  clientId: string;
  items: InvoiceItemInput[];
}

interface UpdateInvoiceData {
  invoiceNumber?: string;
  date?: string;
  dueDate?: string;
  status?: string;
  subtotal?: number;
  tax?: number;
  total?: number;
  clientId?: string;
  items?: InvoiceItemInput[];
}

export async function createInvoice(formData: FormData) {
  const rawData: CreateInvoiceData = {
    invoiceNumber: formData.get('invoiceNumber') as string,
    date: formData.get('date') as string,
    dueDate: formData.get('dueDate') as string,
    status: (() => { const s = formData.get('status'); return s ? normalizeStatus(s as string) : 'DRAFT'; })(),
    subtotal: parseFloat(formData.get('subtotal') as string) || 0,
    tax: parseFloat(formData.get('tax') as string) || 0,
    total: parseFloat(formData.get('total') as string) || 0,
    clientId: (formData.get('clientId') as string) || '',
    items: JSON.parse(formData.get('items') as string || '[]'),
  };

  const invoice = await prisma.invoice.create({
    data: {
      invoiceNumber: rawData.invoiceNumber,
      date: new Date(rawData.date),
      dueDate: new Date(rawData.dueDate),
      status: rawData.status,
      subtotal: rawData.subtotal,
      tax: rawData.tax,
      total: rawData.total,
      clientId: rawData.clientId,
      items: {
        create: rawData.items.map((item) => ({
          description: item.description,
          quantity: item.quantity,
          price: item.price,
        })),
      },
    },
    include: {
      items: true,
      client: true,
    },
  });

  revalidatePath('/invoices');
  revalidatePath('/');
  redirect('/invoices');
}

export async function updateInvoice(id: string, formData: FormData) {
  const rawData: UpdateInvoiceData = {
    invoiceNumber: formData.get('invoiceNumber') as string | undefined,
    date: formData.get('date') as string | undefined,
    dueDate: formData.get('dueDate') as string | undefined,
    status: formData.get('status') ? normalizeStatus(formData.get('status') as string) : undefined,
    subtotal: formData.get('subtotal') ? parseFloat(formData.get('subtotal') as string) : undefined,
    tax: formData.get('tax') ? parseFloat(formData.get('tax') as string) : undefined,
    total: formData.get('total') ? parseFloat(formData.get('total') as string) : undefined,
    clientId: formData.get('clientId') as string | undefined,
    items: formData.get('items') ? JSON.parse(formData.get('items') as string) : undefined,
  };

  const invoice = await prisma.invoice.update({
    where: { id },
    data: {
      ...(rawData.invoiceNumber && { invoiceNumber: rawData.invoiceNumber }),
      ...(rawData.date && { date: new Date(rawData.date) }),
      ...(rawData.dueDate && { dueDate: new Date(rawData.dueDate) }),
      ...(rawData.status && { status: rawData.status }),
      ...(rawData.subtotal !== undefined && { subtotal: rawData.subtotal }),
      ...(rawData.tax !== undefined && { tax: rawData.tax }),
      ...(rawData.total !== undefined && { total: rawData.total }),
      ...(rawData.clientId && { clientId: rawData.clientId }),
      ...(rawData.items && {
        items: {
          deleteMany: {},
          create: rawData.items.map((item) => ({
            description: item.description,
            quantity: item.quantity,
            price: item.price,
          })),
        },
      }),
    },
    include: {
      items: true,
      client: true,
    },
  });

  revalidatePath('/invoices');
  revalidatePath('/');
  redirect('/invoices');
}