import { CollectionDisplayPreferences } from './types';

const LS_KEY = 'moonlit.collectionDisplayPreferences';

interface StoredPrefs {
  disabledCollectionIds: string[];
  expandedCollectionIds: string[];
  hiddenFolderIds: string[];
}

function load(): CollectionDisplayPreferences {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) return { disabledCollectionIds: new Set(), expandedCollectionIds: new Set(), hiddenFolderIds: new Set() };
    const data: StoredPrefs = JSON.parse(raw);
    return {
      disabledCollectionIds: new Set(data.disabledCollectionIds || []),
      expandedCollectionIds: new Set(data.expandedCollectionIds || []),
      hiddenFolderIds: new Set(data.hiddenFolderIds || []),
    };
  } catch {
    return { disabledCollectionIds: new Set(), expandedCollectionIds: new Set(), hiddenFolderIds: new Set() };
  }
}

function save(prefs: CollectionDisplayPreferences) {
  const data: StoredPrefs = {
    disabledCollectionIds: [...prefs.disabledCollectionIds],
    expandedCollectionIds: [...prefs.expandedCollectionIds],
    hiddenFolderIds: [...prefs.hiddenFolderIds],
  };
  try { localStorage.setItem(LS_KEY, JSON.stringify(data)); } catch {}
}

export const CollectionDisplayPreferencesStore = {
  load,
  save,
  isCollectionEnabled(prefs: CollectionDisplayPreferences, collectionId: string): boolean {
    return !prefs.disabledCollectionIds.has(collectionId);
  },
  isCollectionExpanded(prefs: CollectionDisplayPreferences, collectionId: string): boolean {
    return prefs.expandedCollectionIds.has(collectionId);
  },
  isFolderHidden(prefs: CollectionDisplayPreferences, folderId: string): boolean {
    return prefs.hiddenFolderIds.has(folderId);
  },
  toggleCollection(prefs: CollectionDisplayPreferences, collectionId: string): CollectionDisplayPreferences {
    if (prefs.disabledCollectionIds.has(collectionId)) {
      prefs.disabledCollectionIds.delete(collectionId);
    } else {
      prefs.disabledCollectionIds.add(collectionId);
    }
    save(prefs);
    return { ...prefs };
  },
  toggleExpanded(prefs: CollectionDisplayPreferences, collectionId: string): CollectionDisplayPreferences {
    if (prefs.expandedCollectionIds.has(collectionId)) {
      prefs.expandedCollectionIds.delete(collectionId);
    } else {
      prefs.expandedCollectionIds.add(collectionId);
    }
    save(prefs);
    return { ...prefs };
  },
  toggleFolder(prefs: CollectionDisplayPreferences, folderId: string): CollectionDisplayPreferences {
    if (prefs.hiddenFolderIds.has(folderId)) {
      prefs.hiddenFolderIds.delete(folderId);
    } else {
      prefs.hiddenFolderIds.add(folderId);
    }
    save(prefs);
    return { ...prefs };
  },
};
