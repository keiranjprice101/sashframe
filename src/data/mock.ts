import type { HouseholdMember, CalendarEvent, Weather, Photo } from '../lib/types';
import { getStartOfWeek, addDays, formatDateIso } from '../lib/dates';

export const HOUSEHOLD_MEMBERS: Record<string, HouseholdMember> = {
  alex: {
    id: 'alex',
    name: 'Alex',
    color: '#D96B52', // Warm terracotta coral
    bgColor: '#FDF2EE',
    borderColor: '#F5C6BA',
    textColor: '#8C311E',
    initials: 'S'
  },
  sham: {
    id: 'sham',
    name: 'Sham',
    color: '#3B7A66', // Muted sage emerald
    bgColor: '#F0F6F4',
    borderColor: '#B0D5C9',
    textColor: '#1B473A',
    initials: 'Sh'
  }
};

export const MOCK_WEATHER: Weather = {
  temperature: 14,
  unit: '°C',
  condition: 'Cloudy',
  high: 16,
  low: 9
};

export const MOCK_PHOTOS: Photo[] = [
  {
    id: 'photo-1',
    url: '/photos/photo-1.jpg',
    caption: 'Cozy Living Room',
    location: 'Home Sanctuary'
  },
  {
    id: 'photo-2',
    url: '/photos/photo-2.jpg',
    caption: 'Golden Autumn Trail',
    location: 'Highland Walk'
  },
  {
    id: 'photo-3',
    url: '/photos/photo-3.jpg',
    caption: 'Morning Coffee & Sunshine',
    location: 'Kitchen Counter'
  },
  {
    id: 'photo-4',
    url: '/photos/photo-4.jpg',
    caption: 'Alpine Lake Reflection',
    location: 'Sunset Viewpoint'
  }
];

export function getInitialMockEvents(): CalendarEvent[] {
  const mon = getStartOfWeek(new Date());

  const dayStr = (offset: number) => formatDateIso(addDays(mon, offset));

  return [
    {
      id: 'event-1',
      title: 'Work Project Sprint',
      memberId: 'alex',
      date: dayStr(0), // Monday
      startTime: '09:00',
      endTime: '17:00',
      isAllDay: false,
      location: 'Studio Office',
      description: 'Focus block on initial UI wireframes and design tokens.'
    },
    {
      id: 'event-2',
      title: 'Client Strategy Session',
      memberId: 'sham',
      date: dayStr(0), // Monday
      startTime: '09:30',
      endTime: '12:00',
      isAllDay: false,
      location: 'Remote Call',
      description: 'Review Q4 deliverables and launch schedule.'
    },
    {
      id: 'event-3',
      title: 'Dentist Checkup',
      memberId: 'alex',
      date: dayStr(1), // Tuesday
      startTime: '10:30',
      endTime: '11:30',
      isAllDay: false,
      location: 'Downtown Dental Clinic',
      description: 'Routine 6-month cleaning appointment.'
    },
    {
      id: 'event-4',
      title: 'Doctor Appointment',
      memberId: 'sham',
      date: dayStr(1), // Tuesday (overlapping with Dentist!)
      startTime: '11:00',
      endTime: '12:00',
      isAllDay: false,
      location: 'Health Center',
      description: 'Annual health checkup.'
    },
    {
      id: 'event-5',
      title: 'Dinner with Friends',
      memberId: 'alex',
      date: dayStr(2), // Wednesday
      startTime: '19:00',
      endTime: '21:00',
      isAllDay: false,
      location: 'Bistro 18',
      description: 'Catching up with Alex and Sam.'
    },
    {
      id: 'event-6',
      title: 'Theatre Performance',
      memberId: 'sham',
      date: dayStr(2), // Wednesday (overlapping evening!)
      startTime: '19:30',
      endTime: '22:00',
      isAllDay: false,
      location: 'Grand Playhouse',
      description: 'Evening play performance.'
    },
    {
      id: 'event-7',
      title: "Alex's Birthday",
      memberId: 'alex',
      date: dayStr(3), // Thursday
      isAllDay: true,
      description: 'Celebrate Alex! Cake and gifts in the evening.'
    },
    {
      id: 'event-8',
      title: 'Design Review Meeting',
      memberId: 'sham',
      date: dayStr(3), // Thursday
      startTime: '14:00',
      endTime: '15:30',
      isAllDay: false,
      location: 'Conference Room B',
      description: 'Presentation of new component library architecture.'
    },
    {
      id: 'event-9',
      title: 'Weekly Grocery Shopping',
      memberId: 'sham',
      date: dayStr(4), // Friday
      startTime: '16:30',
      endTime: '18:00',
      isAllDay: false,
      location: 'Local Market',
      description: 'Pick up fresh produce and weekend ingredients.'
    },
    {
      id: 'event-10',
      title: 'Farmers Market',
      memberId: 'alex',
      date: dayStr(5), // Saturday
      startTime: '09:30',
      endTime: '11:30',
      isAllDay: false,
      location: 'Town Square',
      description: 'Fresh pastries, organic coffee, and sourdough bread.'
    },
    {
      id: 'event-11',
      title: 'Weekend Trail Hike',
      memberId: 'sham',
      date: dayStr(6), // Sunday
      startTime: '11:00',
      endTime: '15:00',
      isAllDay: false,
      location: 'Greenwood Ridge',
      description: '10km trail walk with mountain viewpoints.'
    }
  ];
}
