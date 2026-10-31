import React from 'react';
import { AnnouncementItem, AnnouncementPriority } from '../types/announcement';

interface AnnouncementCardProps {
  announcement: AnnouncementItem;
}

const priorityStyles: Record<AnnouncementPriority, { badge: string; label: string; border: string }> = {
  Routine: {
    badge: 'bg-blue-100 text-blue-800 border-blue-200',
    label: 'Routine',
    border: 'border-l-blue-500'
  },
  Urgent: {
    badge: 'bg-amber-100 text-amber-800 border-amber-200',
    label: 'Urgent',
    border: 'border-l-amber-500'
  },
  Emergency: {
    badge: 'bg-red-100 text-red-800 border-red-200 animate-pulse',
    label: 'Emergency',
    border: 'border-l-red-600'
  }
};

export const AnnouncementCard: React.FC<AnnouncementCardProps> = ({ announcement }) => {
  const priorityConfig = priorityStyles[announcement.priority] || priorityStyles.Routine;
  const formattedDate = new Date(announcement.publishedAt).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });

  return (
    <article
      data-testid={`announcement-card-${announcement.id}`}
      className={`bg-white rounded-lg shadow-sm border border-gray-200 border-l-4 ${priorityConfig.border} p-5 hover:shadow-md transition-shadow mb-4`}
    >
      <div className="flex items-center justify-between mb-2">
        <span
          data-testid="announcement-priority-badge"
          className={`text-xs font-semibold px-2.5 py-0.5 rounded border ${priorityConfig.badge}`}
        >
          {priorityConfig.label}
        </span>
        <time
          dateTime={announcement.publishedAt}
          className="text-xs text-gray-500 font-medium"
        >
          {formattedDate}
        </time>
      </div>

      <h3 className="text-lg font-bold text-gray-900 mb-2">
        {announcement.title}
      </h3>

      <p className="text-gray-700 whitespace-pre-line text-sm leading-relaxed mb-3">
        {announcement.content}
      </p>

      {announcement.expiresAt && (
        <div className="text-xs text-gray-400 mt-2 italic">
          Expires: {new Date(announcement.expiresAt).toLocaleDateString()}
        </div>
      )}
    </article>
  );
};

export default AnnouncementCard;
