import { KbCategory } from '@/shared/services/knowledgeBaseApi';
import { FolderIcon, ChevronRightIcon } from '@heroicons/react/24/outline';

interface KbCategoryListProps {
  categories: KbCategory[];
  onCategorySelect: (categoryId: string) => void;
  selectedCategory?: string | null;
}

export function KbCategoryList({ 
  categories, 
  onCategorySelect, 
  selectedCategory 
}: KbCategoryListProps) {
  const renderCategory = (category: KbCategory, level = 0) => (
    <div key={category.id} className={`${level > 0 ? 'ml-4' : ''}`}>
      <button
        onClick={() => onCategorySelect(category.id)}
        className={`w-full flex items-center justify-between p-3 rounded-lg text-left transition-colors group hover:bg-theme-primary/5 ${
          selectedCategory === category.id 
            ? 'bg-theme-primary/10 text-theme-primary' 
            : 'text-theme-primary hover:text-theme-primary'
        }`}
      >
        <div className="flex items-center gap-3">
          <FolderIcon className="h-5 w-5 text-theme-secondary group-hover:text-theme-primary" />
          <div>
            <div className="font-medium">{category.name}</div>
            {category.description && (
              <div className="text-sm text-theme-secondary mt-1 line-clamp-1">
                {category.description}
              </div>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-sm text-theme-secondary bg-theme-tertiary px-2 py-1 rounded-full">
            {category.article_count}
          </span>
          <ChevronRightIcon className="h-4 w-4 text-theme-tertiary group-hover:text-theme-primary" />
        </div>
      </button>

      {/* Render child categories */}
      {category.children && category.children.length > 0 && (
        <div className="mt-2 space-y-1">
          {category.children.map(child => renderCategory(child, level + 1))}
        </div>
      )}
    </div>
  );

  if (categories.length === 0) {
    return (
      <div className="text-center py-8">
        <FolderIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
        <p className="text-theme-secondary">No categories found</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {categories.map(category => renderCategory(category))}
    </div>
  );
}