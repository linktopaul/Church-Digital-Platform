import React from 'react';
import { AnnouncementItem } from '../types/announcement';
import { AnnouncementCard } from './AnnouncementCard';

interface AnnouncementFeedProps {
  announcements: AnnouncementItem[];
  isLoading?: boolean;
}

export const AnnouncementFeed: React.FC<AnnouncementFeedProps> = ({
  announcements,
  isLoading = false
}) => {
  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-12 text-gray-500">
        Loading announcements...
      </div>
    );
  }

  if (!announcements || announcements.length === 0) {
    return (
      <div className="text-center py-12 text-gray-500 bg-gray-50 rounded-lg border border-dashed border-gray-300">
        <p className="font-medium">No announcements published yet.</p>
        <p className="text-xs text-gray-400 mt-1">Check back later for pastoral and church updates.</p>
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl mx-auto space-y-4">
      {announcements.map((item) => (
        <AnnouncementCard key={item.id} announcement={item} />
      ))}
    </div>
  );
};

export default AnnouncementFeed;
