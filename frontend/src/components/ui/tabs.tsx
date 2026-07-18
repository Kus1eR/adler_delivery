import { cn } from '../../lib/utils'

interface TabsProps {
  tabs: { key: string; label: string }[]
  activeKey: string
  onChange: (key: string) => void
  className?: string
}

function Tabs({ tabs, activeKey, onChange, className }: TabsProps) {
  return (
    <div className={cn('inline-flex h-10 items-center justify-center rounded-md bg-zinc-100 p-1 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400', className)}>
      {tabs.map((tab) => (
        <button
          key={tab.key}
          onClick={() => onChange(tab.key)}
          className={cn(
            'inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium transition-all cursor-pointer',
            activeKey === tab.key &&
              'bg-white text-zinc-950 shadow-sm dark:bg-zinc-950 dark:text-zinc-50',
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  )
}

export { Tabs }