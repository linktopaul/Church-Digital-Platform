export type AnnouncementPriority = 'Routine' | 'Urgent' | 'Emergency';

export interface AnnouncementItem {
  id: string;
  churchId: string;
  authorId: string;
  title: string;
  content: string;
  priority: AnnouncementPriority;
  publishedAt: string;
  expiresAt?: string | null;
}
