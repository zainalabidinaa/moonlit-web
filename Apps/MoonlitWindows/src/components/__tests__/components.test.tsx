import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, cleanup } from '@testing-library/react';
import RatingBadge from '../RatingBadge';
import CategoryPills from '../CategoryPills';
import StrokeSpinner from '../StrokeSpinner';
import ShimmerCard from '../ShimmerCard';
import EmptyState from '../EmptyState';
import ErrorState from '../ErrorState';
import ProfileAvatar from '../ProfileAvatar';
import LoadingView from '../LoadingView';
import { Folder } from 'lucide-react';

afterEach(cleanup);

describe('RatingBadge', () => {
  it('renders IMDb rating', () => {
    render(<RatingBadge rating="8.5" />);
    expect(screen.getByText('IMDb')).toBeInTheDocument();
    expect(screen.getByText('8.5')).toBeInTheDocument();
  });

  it('strips /10 suffix', () => {
    render(<RatingBadge rating="7.2/10" />);
    expect(screen.getByText('7.2')).toBeInTheDocument();
    expect(screen.queryByText('/10')).toBeNull();
  });

  it('renders compact variant', () => {
    render(<RatingBadge rating="9.0" compact />);
    const badges = screen.getAllByText('IMDb');
    const compactBadge = badges.find((b) =>
      b.closest('.rating-badge')?.className.includes('text-[9px]')
    );
    expect(compactBadge).toBeDefined();
  });

  it('handles numeric rating', () => {
    render(<RatingBadge rating={6.8} />);
    expect(screen.getByText('6.8')).toBeInTheDocument();
  });
});

describe('CategoryPills', () => {
  const categories = [
    { id: 'all', label: 'All' },
    { id: 'action', label: 'Action' },
    { id: 'comedy', label: 'Comedy' },
  ];

  it('renders all categories', () => {
    render(
      <CategoryPills
        categories={categories}
        selected={null}
        onSelect={() => {}}
      />
    );
    expect(screen.getByText('All')).toBeInTheDocument();
    expect(screen.getByText('Action')).toBeInTheDocument();
    expect(screen.getByText('Comedy')).toBeInTheDocument();
  });

  it('highlights selected pill', () => {
    render(
      <CategoryPills
        categories={categories}
        selected="action"
        onSelect={() => {}}
      />
    );
    const buttons = screen.getAllByText('Action');
    const active = buttons.find((b) => b.className.includes('category-pill-active'));
    expect(active).toBeDefined();
  });

  it('shows optional label', () => {
    render(
      <CategoryPills
        categories={categories}
        selected={null}
        onSelect={() => {}}
        label="Genres"
      />
    );
    expect(screen.getByText('Genres')).toBeInTheDocument();
  });
});

describe('StrokeSpinner', () => {
  it('renders SVG with expected elements', () => {
    const { container } = render(<StrokeSpinner size={28} />);
    const svg = container.querySelector('svg');
    expect(svg).toBeInTheDocument();
    const circles = container.querySelectorAll('circle');
    expect(circles.length).toBe(2);
  });

  it('respects size prop', () => {
    const { container } = render(<StrokeSpinner size={44} />);
    const svg = container.querySelector('svg');
    expect(svg?.getAttribute('width')).toBe('44');
    expect(svg?.getAttribute('height')).toBe('44');
  });

  it('has correct aria label', () => {
    render(<StrokeSpinner />);
    const spinners = screen.getAllByRole('img', { name: 'Loading' });
    expect(spinners.length).toBeGreaterThanOrEqual(1);
  });
});

describe('ShimmerCard', () => {
  it('renders a div with shimmer class', () => {
    const { container } = render(<ShimmerCard />);
    const div = container.firstElementChild;
    expect(div).toHaveClass('shimmer');
    expect(div).toHaveClass('rounded-ml-lg');
  });
});

describe('EmptyState', () => {
  it('renders icon, title, and message', () => {
    render(
      <EmptyState
        icon={<Folder data-testid="test-icon" size={20} />}
        title="No items found"
        message="Try adding some content"
      />
    );
    expect(screen.getByTestId('test-icon')).toBeInTheDocument();
    expect(screen.getByText('No items found')).toBeInTheDocument();
    expect(screen.getByText('Try adding some content')).toBeInTheDocument();
  });

  it('renders action button when provided', () => {
    render(
      <EmptyState
        icon={<Folder size={20} />}
        title="Empty"
        action={{ label: 'Add Item', onClick: () => {} }}
      />
    );
    expect(screen.getByText('Add Item')).toBeInTheDocument();
  });
});

describe('ErrorState', () => {
  it('renders with alert icon and retry button', () => {
    render(
      <ErrorState
        title="Something went wrong"
        message="Please try again"
        onRetry={() => {}}
      />
    );
    expect(screen.getByText('Something went wrong')).toBeInTheDocument();
    expect(screen.getByText('Please try again')).toBeInTheDocument();
    expect(screen.getByText('Retry')).toBeInTheDocument();
  });
});

describe('ProfileAvatar', () => {
  it('renders initials when no src', () => {
    render(<ProfileAvatar name="John Doe" />);
    expect(screen.getByText('JD')).toBeInTheDocument();
  });

  it('renders single initial for single name', () => {
    render(<ProfileAvatar name="Admin" />);
    expect(screen.getByText('A')).toBeInTheDocument();
  });

  it('renders image when src provided', () => {
    render(<ProfileAvatar name="User" src="https://example.com/avatar.jpg" />);
    const img = screen.getByAltText('User');
    expect(img).toBeInTheDocument();
    expect(img.tagName).toBe('IMG');
  });

  it('respects size prop', () => {
    const { container } = render(<ProfileAvatar name="JD" size={60} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.width).toBe('60px');
  });

  it('shows admin badge when enabled', () => {
    const { container } = render(
      <ProfileAvatar name="Admin" showBadge />
    );
    const badge = container.querySelector('.bg-moonlit-gold');
    expect(badge).toBeInTheDocument();
  });
});

describe('LoadingView', () => {
  it('renders spinner and caption', () => {
    const { container } = render(<LoadingView />);
    const svg = container.querySelector('svg');
    expect(svg).toBeInTheDocument();
    const text = container.querySelector('span');
    expect(text).toBeInTheDocument();
  });
});
