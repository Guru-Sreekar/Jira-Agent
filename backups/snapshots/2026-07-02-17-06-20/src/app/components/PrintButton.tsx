'use client';

export default function PrintButton() {
  return (
    <button 
      onClick={() => window.print()} 
      className="btn btn-secondary"
    >
      Print
    </button>
  );
}
