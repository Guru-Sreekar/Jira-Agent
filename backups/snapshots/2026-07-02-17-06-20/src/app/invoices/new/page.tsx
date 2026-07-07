import InvoiceForm from '@/app/components/InvoiceForm';
import { prisma } from '@/lib/prisma';

export default async function NewInvoicePage() {
  const clients = await prisma.client.findMany({
    orderBy: { name: 'asc' }
  });

  return (
    <div>
      <InvoiceForm clients={clients} />
    </div>
  );
}
