import { useState } from 'react';
import { motion } from 'framer-motion';
import { SPRING } from '@/lib/design/motion';
import { useTileHalo } from '@/lib/design/artwork-color';
import { User } from 'lucide-react';

interface CastCardProps {
  person: {
    id: string;
    name: string;
    photo?: string;
    character?: string;
  };
  onClick: () => void;
}

export default function CastCard({ person, onClick }: CastCardProps) {
  const [hovering, setHovering] = useState(false);
  const haloColor = useTileHalo(person.photo);

  return (
    <div className="cursor-pointer" style={{ width: 148 }} onClick={onClick}>
      <motion.div
        className="relative"
        animate={{ y: hovering ? -4 : 0 }}
        transition={SPRING.tileHover}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => setHovering(false)}
      >
        <div
          className="overflow-hidden bg-moonlit-elevated"
          style={{
            width: 148,
            height: 170,
            borderTopLeftRadius: 10,
            borderTopRightRadius: 10,
          }}
        >
          {person.photo ? (
            <img
              src={person.photo}
              alt={person.name}
              className="w-full h-full object-cover"
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center">
              <User size={36} className="text-white/20" />
            </div>
          )}
        </div>

        <div
          className="absolute inset-0 pointer-events-none transition-opacity duration-300"
          style={{
            borderTopLeftRadius: 10,
            borderTopRightRadius: 10,
            opacity: hovering ? 1 : 0,
          }}
        >
          {haloColor && (
            <>
              <div
                style={{
                  position: 'absolute',
                  inset: -22,
                  background: haloColor,
                  filter: 'blur(30px)',
                  opacity: 0.66,
                  borderTopLeftRadius: 16,
                  borderTopRightRadius: 16,
                }}
              />
              <div
                style={{
                  position: 'absolute',
                  inset: -46,
                  background: haloColor,
                  filter: 'blur(60px)',
                  opacity: 0.30,
                  borderTopLeftRadius: 16,
                  borderTopRightRadius: 16,
                }}
              />
            </>
          )}
        </div>

        <div
          className="absolute inset-0 border pointer-events-none transition-colors duration-300"
          style={{
            borderTopLeftRadius: 10,
            borderTopRightRadius: 10,
            borderColor: hovering
              ? 'rgba(255,255,255,0.14)'
              : 'rgba(255,255,255,0.05)',
            borderWidth: 0.75,
          }}
        />
      </motion.div>

      <div className="pt-[6px] px-1">
        <p className="text-[11px] font-semibold text-white line-clamp-1">
          {person.name}
        </p>
        {person.character && (
          <p className="text-[10px] text-white/45 line-clamp-1">
            {person.character}
          </p>
        )}
      </div>
    </div>
  );
}
