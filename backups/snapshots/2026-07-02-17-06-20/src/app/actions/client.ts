'use server';

import { prisma } from '@/lib/prisma';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

export async function createClient(formData: FormData) {
  const name = formData.get('name') as string;
  const email = formData.get('email') as string;
  const phone = formData.get('phone') as string;
  const address = formData.get('address') as string;

  if (!name) {
    throw new Error('Name is required');
  }

  await prisma.client.create({
    data: {
      name,
      email,
      phone,
      address,
    },
  });

  revalidatePath('/clients');
  redirect('/clients');
}

export async function updateClient(id: string, formData: FormData) {
  const name = formData.get('name') as string;
  const email = formData.get('email') as string;
  const phone = formData.get('phone') as string;
  const address = formData.get('address') as string;

  if (!name) {
    throw new Error('Name is required');
  }

  await prisma.client.update({
    where: { id },
    data: {
      name,
      email,
      phone,
      address,
    },
  });

  revalidatePath('/clients');
  redirect('/clients');
}

export async function deleteClient(id: string) {
  try {
    await prisma.client.delete({
      where: { id },
    });
  } catch (error) {
    return { error: 'Cannot delete client. They have existing invoices attached. Please delete their invoices first.' };
  }

  revalidatePath('/clients');
  redirect('/clients');
}
