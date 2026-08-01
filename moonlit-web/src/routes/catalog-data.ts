import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';

import { fetchLiveOrganizer, loadCollections, refreshCollections } from '@/lib/collections/repository';
import type { AddonManifest } from '@/lib/types';
import {
  createProfilePreferencesRepository,
  DEFAULT_ARTWORK_PREFERENCES,
  type ArtworkPreferences,
} from '@/lib/preferences/profile-preferences';
import { TMDB_API_KEY } from '@/lib/supabase';

export function useCatalogRowsData(addons: AddonManifest[], profileId: string | null | undefined) {
  const addonKey = addons.map(addon => addon.id).join(',');
  return useQuery({
    queryKey: ['catalog-surfaces', profileId ?? 'guest', addonKey],
    queryFn: async () => {
      const availableRows = await loadCollections(addons, TMDB_API_KEY);
      const organizer = await fetchLiveOrganizer();
      if (!organizer) return availableRows;
      try {
        return await refreshCollections(organizer, addons, TMDB_API_KEY);
      } catch {
        return availableRows;
      }
    },
    enabled: addons.length > 0,
    staleTime: 5 * 60 * 1000,
    placeholderData: previous => previous,
  });
}

export function useArtworkPreferences(profileId: string | null | undefined): ArtworkPreferences {
  const repository = useMemo(() => createProfilePreferencesRepository(), []);
  const cached = useMemo(
    () => repository.loadCached(profileId ?? null, 'artwork').value,
    [profileId, repository],
  );
  const { data = cached } = useQuery({
    queryKey: ['profile-artwork-preferences', profileId ?? 'guest'],
    queryFn: async () => {
      try {
        return (await repository.load(profileId ?? null, 'artwork')).value;
      } catch {
        return DEFAULT_ARTWORK_PREFERENCES;
      }
    },
    initialData: cached,
    staleTime: 5 * 60 * 1000,
  });

  return data;
}
