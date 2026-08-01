export const config = { runtime: 'edge' };

export default function handler(req: Request) {
  void req;
  return new Response('Media proxy disabled', {
    status: 410,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; charset=utf-8',
    },
  });
}
